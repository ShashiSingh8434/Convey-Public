// lib/features/calls/services/call_service.dart
//
// Orchestrates the complete WebRTC call lifecycle:
//   • startCall()   — caller initiates
//   • acceptCall()  — receiver accepts
//   • rejectCall()  — receiver rejects
//   • endCall()     — either party ends (idempotent)
//   • Timeout handling (60 s)
//   • Presence updates (isInCall flag)
//   • Firestore call_history writes
//
// Uses:
//   SignalingService      — RTDB read / write
//   WebRtcService         — PeerConnection / media
//   NotificationApiClient — outbound FCM via server
//
// ──────────────────────────────────────────────────────────────────────────
// Key fixes over original:
//
//  [1] CALLER – candidate watch starts AFTER offer is stored, ensuring the
//      WebRTC PC exists and has a local description before any RTDB event fires.
//
//  [2] RECEIVER – candidate watch starts AFTER createAnswer() returns, so the
//      remote description is already applied and every incoming candidate can
//      be applied immediately (no unnecessary queuing).
//
//  [3] CALLER – _answerApplied flag on WebRtcService prevents setRemoteAnswer()
//      from being called a second time if watchCall() fires again for the same
//      'accepted' status event.
//
//  [4] endCall() / _cleanup() use a single _isCleaningUp guard so concurrent
//      triggers (RTDB 'ended' + onConnectionStateChange FAILED) execute cleanup
//      exactly once.
//
//  [5] _watchCallDocument() skips events that arrive after cleanup has started.
// ──────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../notifications/notification_api_client.dart';
import '../../onboarding/models/user_model.dart';
import '../models/call_model.dart';
import '../models/call_state.dart';
import '../models/ice_candidate_model.dart';
import 'signaling_service.dart';
import 'webrtc_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallService
// ─────────────────────────────────────────────────────────────────────────────

class CallService {
  CallService._();
  static final instance = CallService._();

  final _firestore = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;
  final _signaling = SignalingService.instance;
  final _webrtc = WebRtcService.instance;
  final _uuid = const Uuid();

  // ── State callback — wired by CallNotifier ─────────────────────────────────
  void Function(CallState Function(CallState))? onStateUpdate;

  // ── Subscriptions ──────────────────────────────────────────────────────────
  StreamSubscription<CallModel>? _callWatchSub;
  StreamSubscription<IceCandidateModel>? _remoteCandidatesSub;
  Timer? _timeoutTimer;
  Timer? _durationTimer;

  // ── Call tracking ──────────────────────────────────────────────────────────
  String? _activeCallId;
  bool _isCaller = false;
  DateTime? _callConnectedAt;

  // Guard: prevents double-cleanup from concurrent endCall() triggers.
  bool _isCleaningUp = false;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  // ─────────────────────────────────────────────────────────────────────────
  // Permissions
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _requestCallPermissions({required bool video}) async {
    final permissions = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];
    final result = await permissions.request();
    return permissions.every((p) => result[p]?.isGranted ?? false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // START CALL (caller)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Sequence:
  //  1.  Check receiver busy flag
  //  2.  Emit outgoing state
  //  3.  Create RTDB call document
  //  4.  Request permissions
  //  5.  Initialize WebRTC (creates PC, gets local stream)
  //  6.  Wire WebRTC callbacks
  //  7.  Create SDP offer → store in RTDB
  //  8.  Start watching the call document for answer / status
  //  9.  Start watching receiver's ICE candidates   ← AFTER offer stored
  // 10.  Send FCM incoming_call to receiver
  // 11.  Start 60 s ring timeout
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> startCall({
    required String receiverUid,
    required String receiverName,
    required String? receiverPhotoUrl,
    required String chatId,
    required CallType callType,
  }) async {
    debugPrint(
      '[CALL] startCall → receiver=$receiverUid type=${callType.value}',
    );

    try {
      // 1. Busy check
      final busy = await _isUserBusy(receiverUid);
      if (busy) {
        debugPrint('[CALL] Receiver is busy');
        _emit(
          (s) =>
              s.copyWith(phase: CallPhase.ended, callStatus: CallStatus.busy),
        );
        return;
      }

      final callId = _uuid.v4();
      _activeCallId = callId;
      _isCaller = true;
      _isCleaningUp = false;

      // Resolve our own display info now so it's ready for call history.
      final callerInfo = await _fetchUserInfo(_myUid);

      // 2. Emit outgoing state
      _emit(
        (s) => s.copyWith(
          phase: CallPhase.outgoing,
          callId: callId,
          callType: callType,
          callStatus: CallStatus.ringing,
          remoteUid: receiverUid,
          remoteName: receiverName,
          remotePhotoUrl: receiverPhotoUrl,
          chatId: chatId,
        ),
      );

      // 3. Create RTDB call document
      final callModel = CallModel(
        callId: callId,
        callerId: _myUid,
        receiverId: receiverUid,
        type: callType,
        status: CallStatus.ringing,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _signaling.createCallDocument(callModel);

      // 4. Permissions
      final granted = await _requestCallPermissions(
        video: callType == CallType.video,
      );
      if (!granted) throw Exception('Camera/microphone permissions denied');

      // 5. Initialize WebRTC (creates PeerConnection, acquires local stream)
      final localStream = await _webrtc.initialize(
        isVideo: callType == CallType.video,
      );
      _emit((s) => s.copyWith(localStream: localStream));

      // 6. Wire WebRTC callbacks
      _webrtc.onLocalIceCandidate = (IceCandidateModel candidate) {
        debugPrint('[CALL] Local ICE candidate — sending to RTDB as caller');
        _signaling.sendCandidate(
          callId: callId,
          role: 'caller',
          candidate: candidate,
        );
      };
      _webrtc.onRemoteStream = (MediaStream stream) {
        debugPrint('[CALL] Remote stream received');
        _emit((s) => s.copyWith(remoteStream: stream));
      };
      _webrtc.onConnectionStateChange = _onConnectionStateChange;

      // 7. Create SDP offer and store it
      final offer = await _webrtc.createOffer();
      await _signaling.storeOffer(
        callId: callId,
        offer: SdpDescription(type: offer.type!, sdp: offer.sdp!),
      );
      debugPrint('[CALL] Offer stored');

      // 8. Watch call document (answer + status events)
      _watchCallDocument(callId, callerInfo: callerInfo);

      // 9. Watch receiver ICE candidates
      //    Must come AFTER initialize() so _pc is non-null when candidates arrive.
      //    Remote description is not set yet, so WebRtcService will queue them
      //    and flush after setRemoteAnswer().
      _watchRemoteCandidates(callId: callId, remoteRole: 'receiver');

      // 10. Send FCM push
      await NotificationApiClient.instance.sendIncomingCallNotification(
        receiverId: receiverUid,
        chatId: chatId,
        callId: callId,
        callType: callType.value,
      );
      debugPrint('[CALL] FCM incoming_call sent');

      // 11. 60 s ring timeout
      _startTimeout(
        callId: callId,
        receiverUid: receiverUid,
        callerInfo: callerInfo,
        receiverName: receiverName,
        receiverPhotoUrl: receiverPhotoUrl,
        callType: callType,
      );

      debugPrint('[CALL] startCall complete — waiting for answer');
    } catch (e, st) {
      debugPrint('[CALL] startCall error: $e\n$st');
      await _handleError(e.toString());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCEPT CALL (receiver)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Sequence:
  //  1.  Emit connecting state
  //  2.  Update presence (isInCall = true)
  //  3.  Fetch call document (contains offer)
  //  4.  Request permissions
  //  5.  Initialize WebRTC
  //  6.  Wire WebRTC callbacks (ICE send, remote stream, connection state)
  //  7.  createAnswer(remoteOffer) → sets remote desc, flushes pending ICE
  //  8.  Store answer in RTDB (also sets status → accepted)
  //  9.  Start watching caller ICE candidates   ← AFTER createAnswer so remote
  //                                                description is already set;
  //                                                candidates applied immediately
  // 10.  Send FCM call_accepted to caller
  // 11.  Watch call document for 'ended' / 'connected' status events
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> acceptCall({
    required String callId,
    required String callerUid,
    required String callerName,
    required String? callerPhotoUrl,
    required String chatId,
    required CallType callType,
  }) async {
    debugPrint('[CALL] acceptCall — callId=$callId caller=$callerUid');

    try {
      _activeCallId = callId;
      _isCaller = false;
      _isCleaningUp = false;

      // 1. Emit connecting state
      _emit(
        (s) => s.copyWith(
          phase: CallPhase.connecting,
          callId: callId,
          callType: callType,
          callStatus: CallStatus.accepted,
          remoteUid: callerUid,
          remoteName: callerName,
          remotePhotoUrl: callerPhotoUrl,
          chatId: chatId,
        ),
      );

      // 2. Presence
      await _setInCall(callId: callId, callType: callType, isInCall: true);

      // 3. Fetch offer
      final callDoc = await _signaling.fetchCall(callId);
      if (callDoc == null || callDoc.offer == null) {
        throw Exception('No offer found for call $callId');
      }
      debugPrint('[CALL] Offer fetched — type=${callDoc.offer!.type}');

      // 4. Permissions
      final granted = await _requestCallPermissions(
        video: callType == CallType.video,
      );
      if (!granted) throw Exception('Camera/microphone permissions denied');

      // 5. Initialize WebRTC
      final localStream = await _webrtc.initialize(
        isVideo: callType == CallType.video,
      );
      _emit((s) => s.copyWith(localStream: localStream));

      // 6. Wire callbacks before createAnswer so ICE starts flowing immediately.
      _webrtc.onLocalIceCandidate = (IceCandidateModel candidate) {
        debugPrint('[CALL] Local ICE candidate — sending to RTDB as receiver');
        _signaling.sendCandidate(
          callId: callId,
          role: 'receiver',
          candidate: candidate,
        );
      };
      _webrtc.onRemoteStream = (MediaStream stream) {
        debugPrint('[CALL] Remote stream received');
        _emit((s) => s.copyWith(remoteStream: stream));
      };
      _webrtc.onConnectionStateChange = _onConnectionStateChange;

      // 7. Set remote offer + create answer.
      //    createAnswer() internally calls setRemoteDescription() first, so
      //    _remoteDescriptionSet = true before any ICE candidate is applied.
      final remoteOffer = RTCSessionDescription(
        callDoc.offer!.sdp,
        callDoc.offer!.type,
      );
      final answer = await _webrtc.createAnswer(remoteOffer);
      debugPrint('[CALL] Answer created — setting local description done');

      // 8. Persist answer → triggers status = accepted on RTDB.
      await _signaling.storeAnswer(
        callId: callId,
        answer: SdpDescription(type: answer.type!, sdp: answer.sdp!),
      );
      debugPrint('[CALL] Answer stored in RTDB');

      // 9. Watch caller ICE candidates.
      //    Remote description is now set, so every candidate delivered here
      //    will be applied immediately — no queueing needed.
      _watchRemoteCandidates(callId: callId, remoteRole: 'caller');

      // 10. Notify caller via server FCM.
      await NotificationApiClient.instance.sendCallAccepted(
        callerId: callerUid,
        callId: callId,
      );
      debugPrint('[CALL] FCM call_accepted sent');

      // 11. Watch call document (listen for ended / timeout from caller).
      _watchCallDocument(callId);

      debugPrint('[CALL] acceptCall complete — waiting for peer connection');
    } catch (e, st) {
      debugPrint('[CALL] acceptCall error: $e\n$st');
      await _handleError(e.toString());
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // REJECT CALL (receiver)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> rejectCall({
    required String callId,
    required String callerUid,
  }) async {
    debugPrint('[CALL] rejectCall — callId=$callId');
    try {
      await _signaling.updateCallStatus(
        callId: callId,
        status: CallStatus.rejected,
      );
      await NotificationApiClient.instance.sendCallRejected(
        callerId: callerUid,
        callId: callId,
      );
    } catch (e) {
      debugPrint('[CALL] rejectCall error: $e');
    } finally {
      await _cleanup();
      _emit(
        (s) =>
            s.copyWith(phase: CallPhase.ended, callStatus: CallStatus.rejected),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // END CALL (either party — idempotent)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> endCall() async {
    final callId = _activeCallId;
    debugPrint('[CALL] endCall — callId=$callId isCleaningUp=$_isCleaningUp');

    if (callId == null || _isCleaningUp) {
      debugPrint(
        '[CALL] endCall — skipped (no active call or already cleaning up)',
      );
      return;
    }

    try {
      final durationSeconds = _callConnectedAt != null
          ? DateTime.now().difference(_callConnectedAt!).inSeconds
          : 0;

      await _signaling.updateCallStatus(
        callId: callId,
        status: CallStatus.ended,
      );

      final currentState = _currentState();
      final otherUid = currentState?.remoteUid ?? '';
      if (otherUid.isNotEmpty) {
        await NotificationApiClient.instance.sendCallEnded(
          targetId: otherUid,
          callId: callId,
        );
      }

      await _writeCallHistory(
        callId: callId,
        status: durationSeconds > 0
            ? CallHistoryStatus.completed
            : (_isCaller
                  ? CallHistoryStatus.cancelled
                  : CallHistoryStatus.missed),
        durationSeconds: durationSeconds,
      );
    } catch (e) {
      debugPrint('[CALL] endCall error: $e');
    } finally {
      await _cleanup();
      _emit(
        (s) => s.copyWith(phase: CallPhase.ended, callStatus: CallStatus.ended),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Media controls
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> toggleMute(bool currentMuted) async {
    final next = !currentMuted;
    debugPrint('[CALL] toggleMute → $next');
    await _webrtc.setMuted(next);
    _emit((s) => s.copyWith(isMuted: next));
  }

  Future<void> toggleSpeaker(bool currentSpeakerOn) async {
    final next = !currentSpeakerOn;
    debugPrint('[CALL] toggleSpeaker → $next');
    await _webrtc.setSpeakerOn(next);
    _emit((s) => s.copyWith(isSpeakerOn: next));
  }

  Future<void> toggleVideo(bool currentEnabled) async {
    final next = !currentEnabled;
    debugPrint('[CALL] toggleVideo → $next');
    await _webrtc.setVideoEnabled(next);
    _emit((s) => s.copyWith(isVideoEnabled: next));
  }

  Future<void> switchCamera(bool currentFront) async {
    debugPrint('[CALL] switchCamera');
    await _webrtc.switchCamera();
    _emit((s) => s.copyWith(isFrontCamera: !currentFront));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Watch: call document (status + answer)
  // ─────────────────────────────────────────────────────────────────────────

  void _watchCallDocument(String callId, {AppUser? callerInfo}) {
    _callWatchSub?.cancel();

    debugPrint('[CALL] _watchCallDocument — subscribing callId=$callId');

    _callWatchSub = _signaling.watchCall(callId).listen((CallModel call) async {
      // Ignore events that arrive after we have started cleanup.
      if (_isCleaningUp) {
        debugPrint('[CALL] watchCall event ignored — cleanup in progress');
        return;
      }

      debugPrint(
        '[CALL] watchCall event — status=${call.status.value} '
        'hasAnswer=${call.answer != null} isCaller=$_isCaller',
      );

      switch (call.status) {
        // ── accepted ─────────────────────────────────────────────────────
        // Caller: the receiver has answered → apply remote answer.
        // Receiver: we wrote this status ourselves → no-op.
        case CallStatus.accepted:
          if (_isCaller && call.answer != null) {
            debugPrint(
              '[CALL] watchCall: accepted + answer available — applying remote answer',
            );
            _timeoutTimer?.cancel();
            _timeoutTimer = null;

            await _setInCall(
              callId: callId,
              callType: call.type,
              isInCall: true,
            );

            final remoteAnswer = RTCSessionDescription(
              call.answer!.sdp,
              call.answer!.type,
            );

            try {
              // WebRtcService guards against double-application internally.
              await _webrtc.setRemoteAnswer(remoteAnswer);
              debugPrint('[CALL] Remote answer applied successfully');
            } catch (e, st) {
              debugPrint('[CALL] setRemoteAnswer error: $e\n$st');
              await _handleError('Failed to apply remote answer: $e');
            }
          }
          break;

        // ── connected ────────────────────────────────────────────────────
        // Handled by onConnectionStateChange; no UI action needed here.
        case CallStatus.connected:
          debugPrint(
            '[CALL] watchCall: status=connected (handled by PC callback)',
          );
          break;

        // ── rejected ─────────────────────────────────────────────────────
        case CallStatus.rejected:
          if (_isCaller) {
            debugPrint('[CALL] watchCall: call rejected by receiver');
            _timeoutTimer?.cancel();
            await _writeCallHistory(
              callId: callId,
              status: CallHistoryStatus.rejected,
              durationSeconds: 0,
            );
            await _cleanup();
            _emit(
              (s) => s.copyWith(
                phase: CallPhase.ended,
                callStatus: CallStatus.rejected,
              ),
            );
          }
          break;

        // ── ended ────────────────────────────────────────────────────────
        case CallStatus.ended:
          debugPrint(
            '[CALL] watchCall: status=ended — remote party ended call',
          );
          await _cleanup();
          _emit(
            (s) => s.copyWith(
              phase: CallPhase.ended,
              callStatus: CallStatus.ended,
            ),
          );
          break;

        // ── busy ─────────────────────────────────────────────────────────
        case CallStatus.busy:
          debugPrint('[CALL] watchCall: status=busy');
          _timeoutTimer?.cancel();
          await _cleanup();
          _emit(
            (s) =>
                s.copyWith(phase: CallPhase.ended, callStatus: CallStatus.busy),
          );
          break;

        // ── timeout ──────────────────────────────────────────────────────
        case CallStatus.timeout:
          debugPrint('[CALL] watchCall: status=timeout');
          _timeoutTimer?.cancel();
          await _cleanup();
          _emit(
            (s) => s.copyWith(
              phase: CallPhase.ended,
              callStatus: CallStatus.timeout,
            ),
          );
          break;

        // ── ringing / other ──────────────────────────────────────────────
        default:
          break;
      }
    }, onError: (Object e) => debugPrint('[CALL] watchCall stream error: $e'));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Watch: remote ICE candidates
  // ─────────────────────────────────────────────────────────────────────────

  void _watchRemoteCandidates({
    required String callId,
    required String remoteRole,
  }) {
    _remoteCandidatesSub?.cancel();

    debugPrint(
      '[CALL] _watchRemoteCandidates — callId=$callId remoteRole=$remoteRole',
    );

    _remoteCandidatesSub = _signaling
        .watchRemoteCandidates(callId: callId, remoteRole: remoteRole)
        .listen(
          (IceCandidateModel candidate) async {
            if (_isCleaningUp) {
              debugPrint(
                '[ICE] Remote candidate received after cleanup — discarding',
              );
              return;
            }
            debugPrint(
              '[ICE] Remote candidate received — forwarding to WebRTC',
            );
            await _webrtc.addRemoteCandidate(candidate);
          },
          onError: (Object e) =>
              debugPrint('[ICE] watchRemoteCandidates error: $e'),
        );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PeerConnection state changes
  // ─────────────────────────────────────────────────────────────────────────

  void _onConnectionStateChange(RTCPeerConnectionState state) {
    debugPrint('[CALL] PeerConnection state → $state');

    if (_isCleaningUp) {
      debugPrint(
        '[CALL] Connection state change ignored — cleanup in progress',
      );
      return;
    }

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        debugPrint('[CALL] ✅ Peer connection CONNECTED — media flowing');
        _callConnectedAt = DateTime.now();
        // Update RTDB status for observability (receiver can confirm too).
        _signaling.updateCallStatus(
          callId: _activeCallId!,
          status: CallStatus.connected,
        );
        _startDurationTimer();
        _emit(
          (s) => s.copyWith(
            phase: CallPhase.active,
            callStatus: CallStatus.connected,
          ),
        );
        break;

      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        debugPrint('[CALL] Peer connection CONNECTING…');
        break;

      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Transient disconnection — WebRTC may recover on its own.
        debugPrint(
          '[CALL] ⚠️ Peer temporarily disconnected — waiting for ICE restart',
        );
        break;

      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        debugPrint('[CALL] ❌ Peer connection FAILED — ending call');
        endCall();
        break;

      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        debugPrint('[CALL] Peer connection CLOSED');
        break;

      default:
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ring timeout (60 s)
  // ─────────────────────────────────────────────────────────────────────────

  void _startTimeout({
    required String callId,
    required String receiverUid,
    required AppUser? callerInfo,
    required String receiverName,
    required String? receiverPhotoUrl,
    required CallType callType,
  }) {
    _timeoutTimer?.cancel();
    debugPrint('[CALL] Ring timeout started (60 s)');

    _timeoutTimer = Timer(const Duration(seconds: 60), () async {
      debugPrint('[CALL] Ring timeout fired — callId=$callId');
      try {
        await _signaling.updateCallStatus(
          callId: callId,
          status: CallStatus.timeout,
        );
        await NotificationApiClient.instance.sendMissedCall(
          receiverId: receiverUid,
          callId: callId,
        );
        await _writeCallHistory(
          callId: callId,
          status: CallHistoryStatus.missed,
          durationSeconds: 0,
          callerInfo: callerInfo,
          receiverName: receiverName,
          receiverPhotoUrl: receiverPhotoUrl,
          callType: callType,
        );
      } catch (e) {
        debugPrint('[CALL] Timeout handler error: $e');
      } finally {
        await _cleanup();
        _emit(
          (s) => s.copyWith(
            phase: CallPhase.ended,
            callStatus: CallStatus.timeout,
          ),
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Duration timer
  // ─────────────────────────────────────────────────────────────────────────

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emit((s) => s.copyWith(callDurationSeconds: s.callDurationSeconds + 1));
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Presence
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _setInCall({
    required String callId,
    required CallType callType,
    required bool isInCall,
  }) async {
    final ref = _rtdb.ref('status/$_myUid');
    if (isInCall) {
      await ref.update({
        'isInCall': true,
        'currentCallId': callId,
        'callType': callType.value,
      });
      // Auto-clear presence on disconnect / crash.
      await ref.onDisconnect().update({
        'isInCall': false,
        'currentCallId': null,
        'callType': null,
      });
      debugPrint('[CALL] Presence — isInCall=true');
    } else {
      await ref.update({
        'isInCall': false,
        'currentCallId': null,
        'callType': null,
      });
      await ref.onDisconnect().cancel();
      debugPrint('[CALL] Presence — isInCall=false');
    }
  }

  Future<bool> _isUserBusy(String uid) async {
    final snap = await _rtdb.ref('status/$uid/isInCall').get();
    return snap.exists && snap.value == true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Firestore call history
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _writeCallHistory({
    required String callId,
    required CallHistoryStatus status,
    required int durationSeconds,
    AppUser? callerInfo,
    String? receiverName,
    String? receiverPhotoUrl,
    CallType? callType,
  }) async {
    try {
      debugPrint(
        '[CALL] Writing call history — callId=$callId status=${status.value}',
      );
      final state = _currentState();
      final callTypeResolved = callType ?? state?.callType ?? CallType.audio;

      final callerId = _isCaller ? _myUid : (state?.remoteUid ?? '');
      final receiverId = _isCaller ? (state?.remoteUid ?? '') : _myUid;

      final callerData = callerInfo ?? await _fetchUserInfo(callerId);

      final history = CallHistory(
        callId: callId,
        callerId: callerId,
        callerName:
            callerData?.profile.displayName ??
            callerData?.username ??
            'Unknown',
        callerPhotoUrl: callerData?.profile.photoUrl,
        receiverId: receiverId,
        receiverName: receiverName ?? state?.remoteName ?? 'Unknown',
        receiverPhotoUrl: receiverPhotoUrl ?? state?.remotePhotoUrl,
        type: callTypeResolved,
        status: status,
        durationSeconds: durationSeconds > 0 ? durationSeconds : null,
        startedAt: _callConnectedAt,
        endedAt: durationSeconds > 0 ? DateTime.now() : null,
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection('call_history')
          .doc(callId)
          .set(history.toFirestoreMap());
      debugPrint('[CALL] Call history written');
    } catch (e) {
      debugPrint('[CALL] writeCallHistory error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup — idempotent, guarded by _isCleaningUp
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _cleanup() async {
    if (_isCleaningUp) {
      debugPrint('[CALL] _cleanup — already running, skipping');
      return;
    }
    _isCleaningUp = true;

    debugPrint('[CALL] _cleanup — start');

    _timeoutTimer?.cancel();
    _durationTimer?.cancel();
    _timeoutTimer = null;
    _durationTimer = null;

    await _callWatchSub?.cancel();
    await _remoteCandidatesSub?.cancel();
    _callWatchSub = null;
    _remoteCandidatesSub = null;

    if (_activeCallId != null) {
      await _signaling.cleanupCandidates(
        callId: _activeCallId!,
        role: _isCaller ? 'caller' : 'receiver',
      );
    }

    await _setInCall(
      callId: _activeCallId ?? '',
      callType: CallType.audio,
      isInCall: false,
    );

    await _webrtc.dispose();

    _callConnectedAt = null;
    _activeCallId = null;

    debugPrint('[CALL] _cleanup — complete');
    // Keep _isCleaningUp = true so any late-arriving RTDB callbacks are ignored.
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Error handler
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _handleError(String message) async {
    debugPrint('[CALL] _handleError: $message');
    await _cleanup();
    _emit((s) => s.copyWith(phase: CallPhase.ended, error: message));
  }

  Future<void> handleError(String message) => _handleError(message);

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<AppUser?> _fetchUserInfo(String uid) async {
    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      return snap.exists ? AppUser.fromFirestore(snap) : null;
    } catch (e) {
      debugPrint('[CALL] fetchUserInfo error: $e');
      return null;
    }
  }

  void _emit(CallState Function(CallState) updater) {
    onStateUpdate?.call(updater);
  }

  CallState? _currentState() => _currentStateCallback?.call();

  CallState? Function()? _currentStateCallback;

  void setCurrentStateCallback(CallState? Function() cb) {
    _currentStateCallback = cb;
  }
}

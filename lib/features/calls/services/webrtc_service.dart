// lib/features/calls/services/webrtc_service.dart
//
// Owns the RTCPeerConnection lifecycle.
//
// Key guarantees:
//   • ICE candidates arriving before remote description is set are queued and
//     flushed atomically the moment the remote description is applied.
//   • addRemoteCandidate() is a no-op when the PC has not been initialised.
//   • dispose() is idempotent — safe to call multiple times.
//   • createOffer / createAnswer / setRemoteAnswer all assert PC readiness.

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/ice_candidate_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STUN / TURN configuration
// ─────────────────────────────────────────────────────────────────────────────

const _kIceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
  ],
  // Enable ICE restart support and unified-plan SDP semantics
  'sdpSemantics': 'unified-plan',
};

const _kOfferConstraints = {
  'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
  'optional': [],
};

// ─────────────────────────────────────────────────────────────────────────────
// WebRtcService
// ─────────────────────────────────────────────────────────────────────────────

class WebRtcService {
  WebRtcService._();
  static final instance = WebRtcService._();

  // ── Peer connection & media ───────────────────────────────────────────────

  RTCPeerConnection? _pc;
  MediaStream? _localStream;

  // ── Callbacks (wired by CallService) ─────────────────────────────────────

  /// Fired for every local ICE candidate ready to be sent via signaling.
  void Function(IceCandidateModel)? onLocalIceCandidate;

  /// Fired when the remote media stream is attached.
  void Function(MediaStream)? onRemoteStream;

  /// Fired on every PeerConnection state transition.
  void Function(RTCPeerConnectionState)? onConnectionStateChange;

  // ── ICE candidate queue ───────────────────────────────────────────────────
  // Candidates that arrive before setRemoteDescription() is complete are held
  // here and applied in _flushPendingCandidates() immediately afterward.

  final List<IceCandidateModel> _pendingCandidates = [];

  /// True once setRemoteDescription() has returned successfully on _pc.
  bool _remoteDescriptionSet = false;

  // Guard against concurrent flush / add calls.
  bool _isFlushing = false;

  // Guard against duplicate remote answer application.
  bool _answerApplied = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Public getters
  // ─────────────────────────────────────────────────────────────────────────

  MediaStream? get localStream => _localStream;
  bool get isInitialised => _pc != null;

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1 (caller + receiver): create PeerConnection and acquire local media.
  // ─────────────────────────────────────────────────────────────────────────

  Future<MediaStream> initialize({required bool isVideo}) async {
    debugPrint('[WebRTC] initialize — isVideo=$isVideo');

    // Always start from a clean slate so re-entries are safe.
    await dispose();

    _pc = await createPeerConnection(_kIceServers);
    _remoteDescriptionSet = false;
    _answerApplied = false;
    _pendingCandidates.clear();

    debugPrint('[WebRTC] PeerConnection created');

    // Acquire local media.
    _localStream = await _getLocalStream(isVideo: isVideo);
    debugPrint(
      '[WebRTC] Local stream acquired — tracks: ${_localStream!.getTracks().length}',
    );

    // Add every local track to the connection.
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
      debugPrint('[WebRTC] Added local track: ${track.kind}');
    }

    // ── Wire PC event handlers ─────────────────────────────────────────────

    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      final sdp = candidate.candidate;
      if (sdp == null || sdp.isEmpty) {
        debugPrint('[ICE] Null/empty candidate — gathering complete');
        return;
      }
      debugPrint(
        '[ICE] Local candidate generated: ${sdp.substring(0, sdp.length.clamp(0, 60))}...',
      );
      final model = IceCandidateModel.fromRtcCandidate(candidate);
      onLocalIceCandidate?.call(model);
    };

    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[ICE] Connection state → $state');
    };

    _pc!.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('[ICE] Gathering state → $state');
    };

    _pc!.onSignalingState = (RTCSignalingState state) {
      debugPrint('[WebRTC] Signaling state → $state');
    };

    _pc!.onTrack = (RTCTrackEvent event) {
      debugPrint(
        '[WebRTC] onTrack — kind=${event.track.kind} streams=${event.streams.length}',
      );
      if (event.streams.isNotEmpty) {
        debugPrint('[WebRTC] Remote stream received');
        onRemoteStream?.call(event.streams[0]);
      }
    };

    _pc!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTC] PeerConnection state → $state');
      onConnectionStateChange?.call(state);
    };

    debugPrint('[WebRTC] initialize complete');
    return _localStream!;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2 (caller): create SDP offer.
  // ─────────────────────────────────────────────────────────────────────────

  Future<RTCSessionDescription> createOffer() async {
    _assertInitialised('createOffer');
    debugPrint('[WebRTC] Creating offer…');

    final offer = await _pc!.createOffer(_kOfferConstraints);
    await _pc!.setLocalDescription(offer);

    debugPrint('[WebRTC] Offer created and set as local description');
    return offer;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3 (receiver): apply remote offer, create and return SDP answer.
  // ─────────────────────────────────────────────────────────────────────────

  Future<RTCSessionDescription> createAnswer(
    RTCSessionDescription remoteOffer,
  ) async {
    _assertInitialised('createAnswer');
    debugPrint('[WebRTC] Setting remote offer (type=${remoteOffer.type})…');

    await _pc!.setRemoteDescription(remoteOffer);
    _remoteDescriptionSet = true;
    debugPrint(
      '[WebRTC] Remote offer set — flushing ${_pendingCandidates.length} queued candidates',
    );
    await _flushPendingCandidates();

    debugPrint('[WebRTC] Creating answer…');
    final answer = await _pc!.createAnswer(_kOfferConstraints);
    await _pc!.setLocalDescription(answer);

    debugPrint('[WebRTC] Answer created and set as local description');
    return answer;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 4 (caller): apply the receiver's answer.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setRemoteAnswer(RTCSessionDescription answer) async {
    _assertInitialised('setRemoteAnswer');

    // Guard: only apply the answer once, even if watchCall fires twice.
    if (_answerApplied) {
      debugPrint('[WebRTC] setRemoteAnswer — already applied, skipping');
      return;
    }
    _answerApplied = true;

    debugPrint('[WebRTC] Applying remote answer (type=${answer.type})…');
    await _pc!.setRemoteDescription(answer);
    _remoteDescriptionSet = true;

    debugPrint(
      '[WebRTC] Remote answer set — flushing ${_pendingCandidates.length} queued candidates',
    );
    await _flushPendingCandidates();
    debugPrint('[WebRTC] setRemoteAnswer complete');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Add a remote ICE candidate.
  // If the remote description is not yet set the candidate is queued and will
  // be applied automatically when setRemoteAnswer / createAnswer completes.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> addRemoteCandidate(IceCandidateModel candidate) async {
    if (_pc == null) {
      // PeerConnection not yet created — discard silently.
      debugPrint('[ICE] addRemoteCandidate: PC not initialised, discarding');
      return;
    }

    if (!_remoteDescriptionSet) {
      debugPrint(
        '[ICE] Queuing candidate (remote desc not set yet) — queue size: ${_pendingCandidates.length + 1}',
      );
      _pendingCandidates.add(candidate);
      return;
    }

    await _applyCandidate(candidate);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Media controls
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> setMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    debugPrint('[WebRTC] setMuted=$muted — tracks: ${tracks.length}');
    for (final track in tracks) {
      track.enabled = !muted;
    }
  }

  Future<void> setVideoEnabled(bool enabled) async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    debugPrint('[WebRTC] setVideoEnabled=$enabled — tracks: ${tracks.length}');
    for (final track in tracks) {
      track.enabled = enabled;
    }
  }

  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) {
      debugPrint('[WebRTC] Switching camera');
      await Helper.switchCamera(tracks.first);
    }
  }

  Future<void> setSpeakerOn(bool on) async {
    debugPrint('[WebRTC] setSpeakerOn=$on');
    await Helper.setSpeakerphoneOn(on);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup — idempotent
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    debugPrint('[WebRTC] dispose() called');

    // Clear callbacks first to prevent any in-flight events from firing.
    onLocalIceCandidate = null;
    onRemoteStream = null;
    onConnectionStateChange = null;

    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _answerApplied = false;
    _isFlushing = false;

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        try {
          await track.stop();
        } catch (e) {
          debugPrint('[WebRTC] track.stop() error: $e');
        }
      }
      try {
        await _localStream!.dispose();
      } catch (e) {
        debugPrint('[WebRTC] localStream.dispose() error: $e');
      }
      _localStream = null;
      debugPrint('[WebRTC] Local stream disposed');
    }

    if (_pc != null) {
      try {
        await _pc!.close();
      } catch (e) {
        debugPrint('[WebRTC] pc.close() error: $e');
      }
      _pc = null;
      debugPrint('[WebRTC] PeerConnection closed');
    }

    debugPrint('[WebRTC] dispose() complete');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _flushPendingCandidates() async {
    if (_isFlushing) {
      debugPrint('[ICE] _flushPendingCandidates already running, skipping');
      return;
    }
    _isFlushing = true;

    final toFlush = List<IceCandidateModel>.from(_pendingCandidates);
    _pendingCandidates.clear();

    debugPrint('[ICE] Flushing ${toFlush.length} pending candidates');

    for (final candidate in toFlush) {
      await _applyCandidate(candidate);
    }

    _isFlushing = false;
    debugPrint('[ICE] Flush complete');
  }

  Future<void> _applyCandidate(IceCandidateModel candidate) async {
    if (_pc == null) {
      debugPrint('[ICE] _applyCandidate: PC gone, skipping');
      return;
    }
    try {
      debugPrint(
        '[ICE] Applying candidate: ${candidate.candidate.substring(0, candidate.candidate.length.clamp(0, 60))}…',
      );
      await _pc!.addCandidate(candidate.toRtcCandidate());
      debugPrint('[ICE] Candidate applied successfully');
    } catch (e) {
      debugPrint('[ICE] addCandidate error: $e');
    }
  }

  Future<MediaStream> _getLocalStream({required bool isVideo}) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': isVideo
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
            }
          : false,
    };
    debugPrint('[WebRTC] getUserMedia — constraints: $constraints');
    return navigator.mediaDevices.getUserMedia(constraints);
  }

  void _assertInitialised(String context) {
    if (_pc == null) {
      throw StateError('[WebRTC] $context called before initialize()');
    }
  }
}

// lib/features/calls/providers/call_providers.dart
//
// Riverpod providers for the WebRTC calling feature.
//
//  callStateProvider   — StateNotifier that drives all call UI.
//  callHistoryProvider — StreamProvider of recent call history from Firestore.
//  callServiceProvider — Access to CallService singleton.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/call_model.dart';
import '../models/call_state.dart';
import '../services/call_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallNotifier
// ─────────────────────────────────────────────────────────────────────────────

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(CallState.idle) {
    // Wire CallService callback → state updates
    CallService.instance.onStateUpdate = (updater) {
      if (mounted) state = updater(state);
    };
    CallService.instance.setCurrentStateCallback(() => state);
  }

  @override
  void dispose() {
    CallService.instance.onStateUpdate = null;
    CallService.instance.setCurrentStateCallback(() => null);
    super.dispose();
  }

  // ── Delegating actions to CallService ─────────────────────────────────────

  Future<void> startCall({
    required String receiverUid,
    required String receiverName,
    required String? receiverPhotoUrl,
    required String chatId,
    required CallType callType,
  }) => CallService.instance.startCall(
    receiverUid: receiverUid,
    receiverName: receiverName,
    receiverPhotoUrl: receiverPhotoUrl,
    chatId: chatId,
    callType: callType,
  );

  Future<void> acceptCall({
    required String callId,
    required String callerUid,
    required String callerName,
    required String? callerPhotoUrl,
    required String chatId,
    required CallType callType,
  }) => CallService.instance.acceptCall(
    callId: callId,
    callerUid: callerUid,
    callerName: callerName,
    callerPhotoUrl: callerPhotoUrl,
    chatId: chatId,
    callType: callType,
  );

  Future<void> rejectCall({
    required String callId,
    required String callerUid,
  }) => CallService.instance.rejectCall(callId: callId, callerUid: callerUid);

  Future<void> endCall() => CallService.instance.endCall();

  Future<void> toggleMute() => CallService.instance.toggleMute(state.isMuted);

  Future<void> toggleSpeaker() =>
      CallService.instance.toggleSpeaker(state.isSpeakerOn);

  Future<void> toggleVideo() =>
      CallService.instance.toggleVideo(state.isVideoEnabled);

  Future<void> switchCamera() =>
      CallService.instance.switchCamera(state.isFrontCamera);

  /// Called by NotificationService when an incoming_call FCM arrives.
  void setIncomingCall({
    required String callId,
    required String callerUid,
    required String callerName,
    required String? callerPhotoUrl,
    required String chatId,
    required CallType callType,
  }) {
    state = CallState.idle.copyWith(
      phase: CallPhase.incoming,
      callId: callId,
      callType: callType,
      callStatus: CallStatus.ringing,
      remoteUid: callerUid,
      remoteName: callerName,
      remotePhotoUrl: callerPhotoUrl,
      chatId: chatId,
    );
  }

  /// Called by NotificationService when a call_busy / call_rejected /
  /// call_ended FCM arrives while we are on the OutgoingCallPage.
  void handleRemoteCallEvent(CallStatus status) {
    if (state.phase == CallPhase.idle) return;
    state = state.copyWith(phase: CallPhase.ended, callStatus: status);
  }

  /// Reset to idle (used after navigating away from ended call pages).
  void resetCall() {
    state = CallState.idle;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final callStateProvider = StateNotifierProvider<CallNotifier, CallState>(
  (ref) => CallNotifier(),
);

// ── Call history (Firestore) ─────────────────────────────────────────────────

final callHistoryProvider = StreamProvider<List<CallHistory>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('call_history')
      .where('callerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(CallHistory.fromFirestore).toList());
});

// Combined (as caller OR receiver)
final myCallHistoryProvider = StreamProvider<List<CallHistory>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  // Firestore doesn't support OR on different fields without a composite index.
  // Fetch both and merge client-side.
  final asCaller = FirebaseFirestore.instance
      .collection('call_history')
      .where('callerId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(CallHistory.fromFirestore).toList());

  final asReceiver = FirebaseFirestore.instance
      .collection('call_history')
      .where('receiverId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(CallHistory.fromFirestore).toList());

  return asCaller.asyncMap((callerList) async {
    // Merge after first emission of asReceiver
    final receiverList = await asReceiver.first;
    final merged = [...callerList, ...receiverList];
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  });
});

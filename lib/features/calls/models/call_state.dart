// lib/features/calls/models/call_state.dart
//
// Immutable state object held by CallNotifier.
// Drives all call UI (OutgoingCallPage, IncomingCallPage, AudioCallPage,
// VideoCallPage) and is the single source of truth for call lifecycle.

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallPhase — coarse UI state
// ─────────────────────────────────────────────────────────────────────────────

enum CallPhase {
  idle, // No active call
  outgoing, // Caller is waiting for the receiver to pick up
  incoming, // Receiver sees the incoming call screen
  connecting, // Answer sent / received — WebRTC handshake in progress
  active, // Media flowing
  ended, // Call is over (triggers navigation back)
}

// ─────────────────────────────────────────────────────────────────────────────
// CallState
// ─────────────────────────────────────────────────────────────────────────────

class CallState {
  final CallPhase phase;
  final String? callId;
  final CallType? callType;

  // ── Peer info ──
  final String? remoteUid;
  final String? remoteName;
  final String? remotePhotoUrl;

  // ── ChatId (for ChatPage integration) ──
  final String? chatId;

  // ── Status displayed on OutgoingCallPage ──
  final CallStatus? callStatus; // ringing | busy | rejected | ended | timeout

  // ── Media ──
  final MediaStream? localStream;
  final MediaStream? remoteStream;

  // ── Controls ──
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isFrontCamera;

  // ── Duration (for AudioCallPage) ──
  final int callDurationSeconds;

  // ── Error message ──
  final String? error;

  const CallState({
    this.phase = CallPhase.idle,
    this.callId,
    this.callType,
    this.remoteUid,
    this.remoteName,
    this.remotePhotoUrl,
    this.chatId,
    this.callStatus,
    this.localStream,
    this.remoteStream,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isFrontCamera = true,
    this.callDurationSeconds = 0,
    this.error,
  });

  static const idle = CallState();

  bool get isActive => phase == CallPhase.active;
  bool get hasEnded => phase == CallPhase.ended;

  CallState copyWith({
    CallPhase? phase,
    String? callId,
    CallType? callType,
    String? remoteUid,
    String? remoteName,
    String? remotePhotoUrl,
    String? chatId,
    CallStatus? callStatus,
    MediaStream? localStream,
    MediaStream? remoteStream,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isFrontCamera,
    int? callDurationSeconds,
    String? error,
    // Explicit null-clearing flags
    bool clearRemoteStream = false,
    bool clearLocalStream = false,
    bool clearError = false,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      callType: callType ?? this.callType,
      remoteUid: remoteUid ?? this.remoteUid,
      remoteName: remoteName ?? this.remoteName,
      remotePhotoUrl: remotePhotoUrl ?? this.remotePhotoUrl,
      chatId: chatId ?? this.chatId,
      callStatus: callStatus ?? this.callStatus,
      localStream: clearLocalStream ? null : (localStream ?? this.localStream),
      remoteStream: clearRemoteStream
          ? null
          : (remoteStream ?? this.remoteStream),
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      callDurationSeconds: callDurationSeconds ?? this.callDurationSeconds,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

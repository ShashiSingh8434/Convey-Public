// lib/features/calls/services/signaling_service.dart
//
// Manages all Firebase Realtime Database signaling:
//   • calls/{callId}                         — call document (offer, answer, status)
//   • callCandidates/{callId}/caller|receiver — ICE candidates
//
// This service does NOT touch FCM, Firestore, or WebRtcService directly.
// CallService orchestrates those layers.
//
// Fixes over original:
//   • watchRemoteCandidates() deduplicates by RTDB push-key so rapid
//     onChildAdded events on reconnect never replay the same candidate.
//   • cancelSubscriptions() / cleanupCandidates() are idempotent.
//   • All RTDB references built through a single helper to avoid typos.

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/call_model.dart';
import '../models/ice_candidate_model.dart';

class SignalingService {
  SignalingService._();
  static final instance = SignalingService._();

  final _rtdb = FirebaseDatabase.instance;

  // ── RTDB references ───────────────────────────────────────────────────────

  DatabaseReference _callRef(String callId) => _rtdb.ref('calls/$callId');

  DatabaseReference _candidatesRef(String callId, String role) =>
      _rtdb.ref('callCandidates/$callId/$role');

  // ─────────────────────────────────────────────────────────────────────────
  // Write: create call document
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> createCallDocument(CallModel call) async {
    debugPrint('[SIGNALING] createCallDocument — callId=${call.callId}');
    await _callRef(call.callId).set(call.toRtdbMap());
    debugPrint('[SIGNALING] Call document written');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write: store offer
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> storeOffer({
    required String callId,
    required SdpDescription offer,
  }) async {
    debugPrint('[SIGNALING] storeOffer — callId=$callId type=${offer.type}');
    await _callRef(callId).update({'offer': offer.toMap()});
    debugPrint('[SIGNALING] Offer stored');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write: store answer + mark accepted
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> storeAnswer({
    required String callId,
    required SdpDescription answer,
  }) async {
    debugPrint('[SIGNALING] storeAnswer — callId=$callId type=${answer.type}');
    await _callRef(
      callId,
    ).update({'answer': answer.toMap(), 'status': CallStatus.accepted.value});
    debugPrint('[SIGNALING] Answer stored and status → accepted');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write: update call status
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateCallStatus({
    required String callId,
    required CallStatus status,
  }) async {
    debugPrint(
      '[SIGNALING] updateCallStatus — callId=$callId status=${status.value}',
    );
    await _callRef(callId).update({'status': status.value});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Write: send a local ICE candidate
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendCandidate({
    required String callId,
    required String role, // 'caller' | 'receiver'
    required IceCandidateModel candidate,
  }) async {
    debugPrint('[SIGNALING] sendCandidate — callId=$callId role=$role');
    await _candidatesRef(callId, role).push().set(candidate.toMap());
    debugPrint('[SIGNALING] ICE candidate written to RTDB');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Read: fetch call document once
  // ─────────────────────────────────────────────────────────────────────────

  Future<CallModel?> fetchCall(String callId) async {
    debugPrint('[SIGNALING] fetchCall — callId=$callId');
    final snap = await _callRef(callId).get();
    if (!snap.exists || snap.value == null) {
      debugPrint('[SIGNALING] fetchCall — document not found');
      return null;
    }
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    final call = CallModel.fromRtdb(callId, data);
    debugPrint(
      '[SIGNALING] fetchCall — status=${call.status.value} hasOffer=${call.offer != null}',
    );
    return call;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Listen: call document changes (status + answer)
  // ─────────────────────────────────────────────────────────────────────────

  /// Streams the full call document on every change.
  /// Returns a sentinel model with status=ended when the document disappears.
  Stream<CallModel> watchCall(String callId) {
    debugPrint('[SIGNALING] watchCall — subscribing to callId=$callId');
    return _callRef(callId).onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        debugPrint(
          '[SIGNALING] watchCall — document removed or null, emitting ended',
        );
        return CallModel(
          callId: callId,
          callerId: '',
          receiverId: '',
          type: CallType.audio,
          status: CallStatus.ended,
          createdAt: 0,
        );
      }
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final call = CallModel.fromRtdb(callId, data);
      debugPrint(
        '[SIGNALING] watchCall — status=${call.status.value} hasAnswer=${call.answer != null}',
      );
      return call;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Listen: incoming ICE candidates (with push-key deduplication)
  // ─────────────────────────────────────────────────────────────────────────

  /// Streams each *new* ICE candidate added under [remoteRole].
  ///
  /// Deduplication by push-key prevents the same candidate from being applied
  /// twice if the RTDB listener reattaches after a brief network hiccup.
  Stream<IceCandidateModel> watchRemoteCandidates({
    required String callId,
    required String remoteRole, // 'caller' | 'receiver'
  }) {
    debugPrint(
      '[SIGNALING] watchRemoteCandidates — callId=$callId role=$remoteRole',
    );

    final seen = <String>{};

    return _candidatesRef(callId, remoteRole).onChildAdded
        .where((event) {
          final key = event.snapshot.key ?? '';
          if (seen.contains(key)) {
            debugPrint('[SIGNALING] Duplicate candidate key=$key — skipping');
            return false;
          }
          seen.add(key);
          return true;
        })
        .map((event) {
          final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
          final candidate = IceCandidateModel.fromRtdb(data);
          debugPrint(
            '[SIGNALING] Remote ICE candidate received — key=${event.snapshot.key}',
          );
          return candidate;
        });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup helpers (all idempotent)
  // ─────────────────────────────────────────────────────────────────────────

  /// Remove ICE candidates for a role after the call ends to keep RTDB tidy.
  Future<void> cleanupCandidates({
    required String callId,
    required String role,
  }) async {
    debugPrint('[SIGNALING] cleanupCandidates — callId=$callId role=$role');
    try {
      await _candidatesRef(callId, role).remove();
      debugPrint('[SIGNALING] Candidates removed');
    } catch (e) {
      debugPrint('[SIGNALING] cleanupCandidates error: $e');
    }
  }

  /// Full RTDB call document removal (optional; called by caller after ended).
  Future<void> removeCallDocument(String callId) async {
    debugPrint('[SIGNALING] removeCallDocument — callId=$callId');
    try {
      await _callRef(callId).remove();
      debugPrint('[SIGNALING] Call document removed');
    } catch (e) {
      debugPrint('[SIGNALING] removeCallDocument error: $e');
    }
  }
}

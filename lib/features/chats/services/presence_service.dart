import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/user_presence_model.dart';

/// Manages online presence via Firebase Realtime Database.
///
/// RTDB path: status/{uid}
///   • online       : bool
///   • lastSeen     : ServerValue.timestamp (set on disconnect / background)
class PresenceService {
  PresenceService._();
  static final instance = PresenceService._();

  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  DatabaseReference _statusRef(String uid) => _rtdb.ref('status/$uid');

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once at app startup (after Firebase.initializeApp).
  /// Marks the current user online and registers an onDisconnect handler
  /// so the status flips to offline if the connection drops.
  Future<void> initPresence() async {
    final uid = _currentUid;
    if (uid == null) return;

    final ref = _statusRef(uid);

    await ref.onDisconnect().update({
      'online': false,
      'lastSeen': ServerValue.timestamp,

      'isInCall': false,
      'currentCallId': null,
      'callType': null,
    });

    await ref.update({
      'online': true,
      'lastSeen': ServerValue.timestamp,

      'isInCall': false,
      'currentCallId': null,
      'callType': null,
    });
  }

  // ── App lifecycle ─────────────────────────────────────────────────────────

  /// Call when the app comes back to the foreground (AppLifecycleState.resumed).
  Future<void> setOnline() async {
    final uid = _currentUid;
    if (uid == null) return;
    await _statusRef(uid).update({'online': true});
  }

  /// Call when the app goes to the background or is paused/detached.
  Future<void> setOffline() async {
    final uid = _currentUid;
    if (uid == null) return;
    await _statusRef(
      uid,
    ).update({'online': false, 'lastSeen': ServerValue.timestamp});
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Streams the presence of [uid] in real time.
  Stream<UserPresence> watchPresence(String uid) {
    return _statusRef(uid).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        return UserPresence.offline(uid);
      }
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      return UserPresence.fromRtdb(uid, data);
    });
  }

  // ── One-shot read ─────────────────────────────────────────────────────────

  Future<UserPresence> getPresence(String uid) async {
    final snap = await _statusRef(uid).get();
    if (!snap.exists || snap.value == null) return UserPresence.offline(uid);
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    return UserPresence.fromRtdb(uid, data);
  }

  // ---Calls------------------------------------------------------------------

  Future<void> startCall({
    required String callId,
    required String callType,
  }) async {
    final uid = _currentUid;
    if (uid == null) return;

    await _statusRef(
      uid,
    ).update({'isInCall': true, 'currentCallId': callId, 'callType': callType});
  }

  Future<void> endCall() async {
    final uid = _currentUid;
    if (uid == null) return;

    await _statusRef(
      uid,
    ).update({'isInCall': false, 'currentCallId': null, 'callType': null});
  }

  Future<bool> isUserBusy(String uid) async {
    final presence = await getPresence(uid);
    return presence.isInCall;
  }

  Stream<String?> watchCurrentCallId(String uid) {
    return _statusRef(
      uid,
    ).child('currentCallId').onValue.map((e) => e.snapshot.value as String?);
  }
}

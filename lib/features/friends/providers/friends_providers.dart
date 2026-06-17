import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/models/user_model.dart';
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/relationship_status.dart';
import '../services/friend_service.dart';

// ── Current user uid shortcut ─────────────────────────────────────────────

final currentUidProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

// ── Received requests (stream) ────────────────────────────────────────────

final receivedRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FriendService.instance.getReceivedRequests(uid);
});

// ── Sent requests (stream) ────────────────────────────────────────────────

final sentRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FriendService.instance.getSentRequests(uid);
});

// ── Friendships (stream) ──────────────────────────────────────────────────

final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FriendService.instance.getFriends(uid);
});

// ── Friend user docs (stream, derived from friendships) ───────────────────
//
// For each Friendship we load the other user's Firestore document as a
// real-time stream. We combine them into one list so FriendsPage can
// just watch a single provider.

final friendUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FriendService.instance.getFriends(uid).asyncMap((friendships) async {
    if (friendships.isEmpty) return [];
    final futures = friendships.map((f) {
      final otherUid = f.otherUid(uid);
      return FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .get()
          .then((snap) => snap.exists ? AppUser.fromFirestore(snap) : null);
    });
    final results = await Future.wait(futures);
    return results.whereType<AppUser>().toList();
  });
});

// ── Relationship status (future, keyed by otherUid) ───────────────────────

final relationshipStatusProvider =
    FutureProvider.family<RelationshipStatus, String>((ref, otherUid) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return RelationshipStatus.notFriend;
  return FriendService.instance.getRelationshipStatus(
    currentUid: uid,
    otherUid: otherUid,
  );
});

// ── Received request count badge ─────────────────────────────────────────

final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(receivedRequestsProvider).maybeWhen(
    data: (list) => list.length,
    orElse: () => 0,
  );
});

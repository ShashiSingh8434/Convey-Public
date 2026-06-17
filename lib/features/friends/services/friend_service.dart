import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../onboarding/models/user_model.dart';
import '../models/friend_request_model.dart';
import '../models/friendship_model.dart';
import '../models/relationship_status.dart';

class FriendService {
  FriendService._();
  static final instance = FriendService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Deterministic friendship document ID — always consistent regardless
  /// of which user initiates the lookup.
  static String getFriendshipId(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  String get _currentUid => FirebaseAuth.instance.currentUser!.uid;

  // ── Relationship status ───────────────────────────────────────────────────

  /// Returns the [RelationshipStatus] between [currentUid] and [otherUid].
  /// All checks are done server-side; no local caching is applied here.
  Future<RelationshipStatus> getRelationshipStatus({
    required String currentUid,
    required String otherUid,
  }) async {
    if (currentUid == otherUid) return RelationshipStatus.self;

    // Check friendship first (most common hot-path for existing friends)
    final friendshipId = getFriendshipId(currentUid, otherUid);
    final friendshipSnap = await _db
        .collection('friendships')
        .doc(friendshipId)
        .get();
    if (friendshipSnap.exists) return RelationshipStatus.friend;

    // Check pending requests in both directions with a single collection
    // group-style query using two targeted queries (no index required).
    final sentSnap = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: currentUid)
        .where('toUid', isEqualTo: otherUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (sentSnap.docs.isNotEmpty) return RelationshipStatus.requestSent;

    final receivedSnap = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: otherUid)
        .where('toUid', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (receivedSnap.docs.isNotEmpty) return RelationshipStatus.requestReceived;

    return RelationshipStatus.notFriend;
  }

  // ── Friend Requests ───────────────────────────────────────────────────────

  /// Sends a friend request from [fromUid] to [toUid].
  ///
  /// Validates:
  /// - Not self
  /// - No existing friendship
  /// - No existing pending request in either direction
  Future<void> sendFriendRequest({
    required String fromUid,
    required String toUid,
    String message = "Hi, let's connect on Convey!",
  }) async {
    if (fromUid == toUid) throw FriendException('Cannot add yourself.');

    final status = await getRelationshipStatus(
      currentUid: fromUid,
      otherUid: toUid,
    );

    switch (status) {
      case RelationshipStatus.friend:
        throw FriendException('You are already friends.');
      case RelationshipStatus.requestSent:
        throw FriendException('Friend request already sent.');
      case RelationshipStatus.requestReceived:
        throw FriendException(
          'This user has already sent you a friend request.',
        );
      case RelationshipStatus.self:
        throw FriendException('Cannot add yourself.');
      case RelationshipStatus.notFriend:
        break;
    }

    await _db.collection('friend_requests').add({
      'fromUid': fromUid,
      'toUid': toUid,
      'message': message.trim().isEmpty
          ? "Hi, let's connect on Convey!"
          : message.trim(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'respondedAt': null,
    });
  }

  /// Withdraws (deletes) a pending request sent by [fromUid] to [toUid].
  Future<void> withdrawFriendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    final snap = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: fromUid)
        .where('toUid', isEqualTo: toUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) throw FriendException('Request not found.');
    await snap.docs.first.reference.delete();
  }

  /// Accepts a pending friend request atomically.
  ///
  /// In a single Firestore transaction:
  /// 1. Updates request status → accepted
  /// 2. Creates friendship document
  Future<void> acceptFriendRequest({required String requestId}) async {
    final requestRef = _db.collection('friend_requests').doc(requestId);

    await _db.runTransaction((tx) async {
      final requestSnap = await tx.get(requestRef);
      if (!requestSnap.exists) throw FriendException('Request not found.');

      final data = requestSnap.data() as Map<String, dynamic>;
      if (data['status'] != 'pending') {
        throw FriendException('Request is no longer pending.');
      }

      final fromUid = data['fromUid'] as String;
      final toUid = data['toUid'] as String;
      final friendshipId = getFriendshipId(fromUid, toUid);
      final friendshipRef = _db.collection('friendships').doc(friendshipId);

      tx.update(requestRef, {
        'status': 'accepted',
        'respondedAt': FieldValue.serverTimestamp(),
      });

      tx.set(friendshipRef, {
        'user1': fromUid.compareTo(toUid) <= 0 ? fromUid : toUid,
        'user2': fromUid.compareTo(toUid) <= 0 ? toUid : fromUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Rejects a pending friend request (marks as rejected, keeps history).
  Future<void> rejectFriendRequest({required String requestId}) async {
    await _db.collection('friend_requests').doc(requestId).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a friendship document. Does not delete request history.
  Future<void> removeFriend({
    required String currentUid,
    required String otherUid,
  }) async {
    final friendshipId = getFriendshipId(currentUid, otherUid);
    await _db.collection('friendships').doc(friendshipId).delete();
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  /// Stream of pending requests received by [uid].
  Stream<List<FriendRequest>> getReceivedRequests(String uid) {
    return _db
        .collection('friend_requests')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => FriendRequest.fromFirestore(d)).toList(),
        );
  }

  /// Stream of pending requests sent by [uid].
  Stream<List<FriendRequest>> getSentRequests(String uid) {
    return _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => FriendRequest.fromFirestore(d)).toList(),
        );
  }

  /// Stream of all friendship documents involving [uid].
  Stream<List<Friendship>> getFriends(String uid) {
    return _db
        .collection('friendships')
        .where(
          Filter.or(
            Filter('user1', isEqualTo: uid),
            Filter('user2', isEqualTo: uid),
          ),
        )
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => Friendship.fromFirestore(d)).toList(),
        );
  }

  /// Returns true if a friendship exists between [uidA] and [uidB].
  Future<bool> areFriends(String uidA, String uidB) async {
    final id = getFriendshipId(uidA, uidB);
    final snap = await _db.collection('friendships').doc(id).get();
    return snap.exists;
  }

  // ── User Search ───────────────────────────────────────────────────────────

  /// Searches users by [usernameLower] prefix.
  ///
  /// Firestore range query trick: usernameLower >= query and
  /// usernameLower < query + '\uf8ff' gives prefix matching.
  /// Excludes the current user.
  Future<List<AppUser>> searchUsers({
    required String query,
    required String currentUid,
    int limit = 20,
  }) async {
    if (query.isEmpty) return [];

    final lower = query.toLowerCase().trim();
    final snap = await _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: lower)
        .where('usernameLower', isLessThan: '${lower}\uf8ff')
        .limit(limit + 1) // fetch one extra so we know if there's a next page
        .get();

    return snap.docs
        .map((d) => AppUser.fromFirestore(d))
        .where((u) => u.uid != currentUid)
        .take(limit)
        .toList();
  }

  /// Paginated discovery query — loads users ordered by usernameLower,
  /// excluding the current user.
  Future<({List<AppUser> users, DocumentSnapshot? lastDoc})> discoverUsers({
    required String currentUid,
    int pageSize = 15,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _db
        .collection('users')
        .where('profileCompleted', isEqualTo: true)
        .orderBy('usernameLower')
        .limit(pageSize + 1);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final docs = snap.docs.where((d) => d.id != currentUid).toList();
    final hasMore = docs.length > pageSize;
    final pageUsers = docs
        .take(pageSize)
        .map((d) => AppUser.fromFirestore(d))
        .toList();
    final lastDoc = hasMore && pageUsers.isNotEmpty ? docs[pageSize - 1] : null;

    return (users: pageUsers, lastDoc: lastDoc);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPTION
// ─────────────────────────────────────────────────────────────────────────────

class FriendException implements Exception {
  final String message;
  const FriendException(this.message);

  @override
  String toString() => message;
}

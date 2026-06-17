import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';

class UserService {
  UserService._();
  static final instance = UserService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Username ──────────────────────────────────────────────────────────────

  /// Non-transactional read used only for live UI availability feedback.
  /// The actual atomic claim happens inside [claimUsername].
  Future<bool> isUsernameAvailable(String usernameLower) async {
    final doc = await _db.collection('usernames').doc(usernameLower).get();
    return !doc.exists;
  }

  /// Atomically reserves [username] for [uid].
  ///
  /// Uses a Firestore transaction so two concurrent callers cannot both
  /// succeed — the second one will see the document already exists and
  /// throw [UsernameAlreadyTakenException].
  Future<void> claimUsername({
    required String uid,
    required String username,
  }) async {
    final usernameLower = username.toLowerCase();
    final usernameRef = _db.collection('usernames').doc(usernameLower);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((transaction) async {
      final usernameSnap = await transaction.get(usernameRef);

      if (usernameSnap.exists) {
        // Another user claimed this username between the UI check and submit
        throw UsernameAlreadyTakenException(username);
      }

      // Atomically write both documents
      transaction.set(usernameRef, {'uid': uid});

      transaction.update(userRef, {
        'username': username,
        'usernameLower': usernameLower,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<void> updateProfile({
    required String uid,
    required UserProfile profile,
  }) async {
    await _db.collection('users').doc(uid).update({
      'profile': profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateSocial({
    required String uid,
    required UserSocial social,
  }) async {
    await _db.collection('users').doc(uid).update({
      'social': social.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves profile + social + sets profileCompleted = true in one write.
  Future<void> completeOnboarding({
    required String uid,
    required UserProfile profile,
    required UserSocial social,
  }) async {
    await _db.collection('users').doc(uid).update({
      'profile': profile.toMap(),
      'social': social.toMap(),
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeProfile({required String uid}) async {
    await _db.collection('users').doc(uid).update({
      'profileCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateUserFields({
    required String uid,
    required Map<String, dynamic> fields,
  }) async {
    await _db.collection('users').doc(uid).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXCEPTIONS
// ─────────────────────────────────────────────────────────────────────────────

class UsernameAlreadyTakenException implements Exception {
  final String username;
  const UsernameAlreadyTakenException(this.username);

  @override
  String toString() => '@$username is already taken. Please choose another.';
}

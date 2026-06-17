// lib/features/auth/services/auth_service.dart
//
// Changes from original:
//   • signOut() now calls NotificationService.removeCurrentToken() before
//     signing the user out of Firebase. This removes only the current device's
//     FCM token from Firestore, leaving tokens for other devices intact.
//   • Import added for NotificationService.
//
// Everything else is unchanged.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../notifications/notification_service.dart';
import '../../chats/services/presence_service.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> signInWithGoogle() async {
    UserCredential result;

    if (kIsWeb) {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      result = await _auth.signInWithPopup(googleProvider);
    } else {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize();

      final account = await googleSignIn.authenticate();
      final auth = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
      result = await _auth.signInWithCredential(credential);
    }

    final user = result.user;
    if (user == null) return;

    await PresenceService.instance.initPresence();
    final userRef = _firestore.collection('users').doc(user.uid);
    final doc = await userRef.get();

    if (!doc.exists) {
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'username': null,
        'usernameLower': null,
        'profileCompleted': false,
        'fcmTokens': [], // Initialize empty token list for new users
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'profile': {
          'displayName': user.displayName,
          'about': 'Hey there I am using Convey !!!',
          'photoUrl': user.photoURL,
        },
        'social': {'github': null, 'instagram': null, 'linkedin': null},
      });
    }

    // Register FCM token after successful sign-in.
    // NotificationService.initialize() runs at app start, but the user
    // may not have been signed in at that point. Calling this after
    // sign-in ensures the token is always saved.
    // ignore: unawaited_futures
    NotificationService.instance.sendChatNotification;
  }

  Future<void> signOut() async {
    // 1. Remove this device's FCM token from Firestore BEFORE sign-out,
    //    while we still have an authenticated Firebase session to write with.
    await NotificationService.instance.removeCurrentToken();

    // 2. Go offline in presence system.
    await PresenceService.instance.setOffline();

    // 3. Sign out of Google and Firebase.
    if (!kIsWeb) {
      await GoogleSignIn.instance.signOut();
    }
    await _auth.signOut();
  }
}

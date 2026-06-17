import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'notification_service.dart';
import 'active_chat_service.dart';

// ── NotificationService provider ──────────────────────────────────────────────

/// Access the singleton NotificationService anywhere in the widget tree.
/// You rarely need this directly — prefer calling NotificationService.instance.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);

// ── Active chat provider ───────────────────────────────────────────────────────

/// Tracks the chatId the current user is actively viewing.
///
/// Updated by ChatPage (open/close) and read by:
///   • NotificationService — suppresses foreground toasts for the active chat.
///   • AppLifecycleHandler — clears RTDB node when app is backgrounded.
///
/// null  → user is not in any chat screen.
/// non-null → user is viewing this chatId.
final activeChatProvider = StateProvider<String?>((ref) => null);

// ── ActiveChatService provider ────────────────────────────────────────────────

/// Access the singleton ActiveChatService anywhere in the widget tree.
final activeChatServiceProvider = Provider<ActiveChatService>(
  (ref) => ActiveChatService.instance,
);

/// Watches Firebase auth state and automatically manages the FCM token.
///
/// - User signs in  → registers token
/// - User signs out → token was already removed by AuthService.signOut()
///                    but this acts as a safety net
/// - Token rotates  → onTokenRefresh in NotificationService handles it
///
/// Simply ref.watch() this anywhere once (e.g. in your root widget or
/// AppLifecycleHandler) to activate it. It does nothing on its own
/// until someone watches it.
final fcmTokenSyncProvider = StreamProvider<void>((ref) async* {
  await for (final user in FirebaseAuth.instance.authStateChanges()) {
    if (user != null) {
      // User just signed in (or app restarted with active session) — register token.
      await NotificationService.instance.registerToken();
    }
    // Sign-out case: AuthService.signOut() already removed the token
    // before Firebase signed the user out, so nothing to do here.
  }
});

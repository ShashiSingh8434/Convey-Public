// lib/core/notifications/active_chat_service.dart
//
// Manages the RTDB node: activeChats/{uid}
//
// Schema:
//   activeChats/{uid}: { chatId: String, updatedAt: int (epoch ms) }
//
// Used by:
//   • ChatPage — set on open, clear on close
//   • AppLifecycleHandler — clear when app is backgrounded
//   • Communication Server — reads to suppress notifications when user
//     is actively viewing that chat (server-side suppression is a bonus;
//     the Flutter client also suppresses in NotificationService)
//
// No Riverpod dependency here — this is a pure service singleton
// that can be called from anywhere including non-widget code.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class ActiveChatService {
  ActiveChatService._();
  static final instance = ActiveChatService._();

  final _rtdb = FirebaseDatabase.instance;

  DatabaseReference? _activeChatRef;

  // ── Set ────────────────────────────────────────────────────────────────────

  /// Records that the current user is viewing [chatId].
  /// Also registers an onDisconnect handler so RTDB clears the value
  /// automatically if the client disconnects (e.g. force-quit, network drop).
  Future<void> setActiveChat(String chatId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _activeChatRef = _rtdb.ref('activeChats/$uid');

    final payload = {
      'chatId': chatId,
      'updatedAt': ServerValue.timestamp,
    };

    try {
      // On-disconnect cleanup — survives force-quit and network drops.
      await _activeChatRef!.onDisconnect().remove();
      await _activeChatRef!.set(payload);
    } catch (e) {
      debugPrint('[ActiveChatService] setActiveChat failed: $e');
    }
  }

  // ── Clear ──────────────────────────────────────────────────────────────────

  /// Removes the active chat record. Call this when ChatPage is disposed
  /// or the app moves to background.
  Future<void> clearActiveChat() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Cancel the onDisconnect handler first so it doesn't fire redundantly.
      await _activeChatRef?.onDisconnect().cancel();
      await _rtdb.ref('activeChats/$uid').remove();
      _activeChatRef = null;
    } catch (e) {
      debugPrint('[ActiveChatService] clearActiveChat failed: $e');
    }
  }

  // ── Read (optional, mostly for debugging) ─────────────────────────────────

  /// Returns the chatId the given user is currently viewing, or null.
  /// Primarily consumed by the Communication Server; exposed here for
  /// completeness and local testing.
  Future<String?> getActiveChatId(String uid) async {
    try {
      final snap = await _rtdb.ref('activeChats/$uid').get();
      if (!snap.exists || snap.value == null) return null;
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      return data['chatId'] as String?;
    } catch (e) {
      debugPrint('[ActiveChatService] getActiveChatId failed: $e');
      return null;
    }
  }
}

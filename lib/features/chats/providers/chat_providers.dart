import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../onboarding/models/user_model.dart';
import '../models/chat_model.dart';
import '../models/chat_message_model.dart';
import '../models/read_receipt_model.dart';
import '../models/typing_state_model.dart';
import '../models/user_presence_model.dart';
import '../services/chat_service.dart';
import '../services/presence_service.dart';
import '../services/read_receipt_service.dart';
import '../services/typing_service.dart';

// ── Chat list (stream) ────────────────────────────────────────────────────────

final userChatsProvider = StreamProvider<List<Chat>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return ChatService.instance.getUserChats(uid);
});

// ── Per-chat participant info (future, keyed by chatId) ───────────────────────

final chatParticipantProvider = FutureProvider.family<AppUser?, String>((
  ref,
  chatId,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  final chatSnap = await FirebaseFirestore.instance
      .collection('chats')
      .doc(chatId)
      .get();
  if (!chatSnap.exists) return null;

  final chat = Chat.fromFirestore(chatSnap);
  final otherUid = chat.otherUid(uid);
  if (otherUid.isEmpty) return null;

  final userSnap = await FirebaseFirestore.instance
      .collection('users')
      .doc(otherUid)
      .get();
  return userSnap.exists ? AppUser.fromFirestore(userSnap) : null;
});

// ── Message notifier ──────────────────────────────────────────────────────────

class MessagesNotifier extends AsyncNotifier<List<ChatMessage>> {
  MessagesNotifier(this._chatId);

  final String _chatId;
  bool _hasMore = true;
  bool _loadingMore = false;
  StreamSubscription<ChatMessage>? _liveSub;

  @override
  Future<List<ChatMessage>> build() async {
    ref.onDispose(() => _liveSub?.cancel());

    final messages = await ChatService.instance.loadInitialMessages(_chatId);
    _hasMore = messages.length >= 30;

    final afterTs = messages.isNotEmpty ? messages.last.createdAt : 0;

    await _liveSub?.cancel();

    _liveSub = ChatService.instance
        .listenForNewMessages(chatId: _chatId, afterTimestamp: afterTs)
        .listen(
          (msg) {
            final current = state.asData?.value ?? [];
            if (!current.any((m) => m.id == msg.id)) {
              state = AsyncData([...current, msg]);
            }
          },
          onError: (e) {
            // ignore: avoid_print
            print('Realtime error: $e');
          },
        );

    return messages;
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loadingMore) return;
    final current = state.value;
    if (current == null || current.isEmpty) return;

    _loadingMore = true;
    try {
      final older = await ChatService.instance.loadOlderMessages(
        chatId: _chatId,
        oldestTimestamp: current.first.createdAt,
      );
      _hasMore = older.length >= 30;
      state = AsyncData([...older, ...current]);
    } finally {
      _loadingMore = false;
    }
  }

  bool get hasMore => _hasMore;
}

final messagesProvider =
    AsyncNotifierProvider.family<MessagesNotifier, List<ChatMessage>, String>(
      (chatId) => MessagesNotifier(chatId),
    );

// ── Recording state ───────────────────────────────────────────────────────────

/// Tracks whether the microphone is actively recording in a given chat.
/// Keyed by chatId so multiple chat pages (if ever stacked) don't conflict.
final recordingStateProvider = StateProvider.family<bool, String>(
  (ref, chatId) => false,
);

// ── Presence provider (keyed by uid) ─────────────────────────────────────────

final presenceProvider = StreamProvider.family<UserPresence, String>((
  ref,
  uid,
) {
  if (uid.isEmpty) return Stream.value(UserPresence.offline(uid));
  return PresenceService.instance.watchPresence(uid);
});

// ── Typing provider (keyed by "{chatId}|{otherUid}") ─────────────────────────

final typingProvider = StreamProvider.family<TypingState, String>((
  ref,
  compositeKey,
) {
  final parts = compositeKey.split('|');
  if (parts.length != 2) {
    return Stream.value(TypingState.idle('', ''));
  }
  final chatId = parts[0];
  final otherUid = parts[1];
  return TypingService.instance.watchTyping(chatId: chatId, otherUid: otherUid);
});

/// Helper to build the composite key for [typingProvider].
String typingKey(String chatId, String otherUid) => '$chatId|$otherUid';

// ── Read receipt provider (keyed by "{chatId}|{uid}") ────────────────────────

final readReceiptProvider = StreamProvider.family<ReadReceipt, String>((
  ref,
  compositeKey,
) {
  final parts = compositeKey.split('|');
  if (parts.length != 2) {
    return Stream.value(ReadReceipt.empty('', ''));
  }
  final chatId = parts[0];
  final uid = parts[1];
  return ReadReceiptService.instance.watchReceipt(chatId: chatId, uid: uid);
});

/// Helper to build the composite key for [readReceiptProvider].
String readKey(String chatId, String uid) => '$chatId|$uid';

// ── Unread count provider (keyed by chatId) ───────────────────────────────────

final unreadCountProvider = StreamProvider.family<int, String>((ref, chatId) {
  return ReadReceiptService.instance.watchUnreadCount(chatId: chatId);
});

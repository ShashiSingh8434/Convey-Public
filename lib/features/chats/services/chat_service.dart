// lib/features/chats/services/chat_service.dart
//
// Changes from original:
//   • sendTextMessage(), sendImageMessage(), sendAudioMessage() each call
//     NotificationService.sendChatNotification() after writing to Firestore.
//   • The notification call is fire-and-forget (unawaited, wrapped in try/catch
//     inside NotificationService) so a server failure never blocks message delivery.
//   • To route the notification to the correct recipient we need the otherUid,
//     so each send method now accepts a required `recipientUid` parameter.
//
// IMPORTANT — Callers must pass recipientUid:
//   All three send methods have a new required parameter.
//   Update ChatInputBar (or wherever these are called) accordingly.
//   See the note at the bottom of this file.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../notifications/notification_service.dart';
import '../models/chat_model.dart';
import '../models/chat_message_model.dart';

class ChatService {
  ChatService._();
  static final instance = ChatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _currentUid => FirebaseAuth.instance.currentUser!.uid;

  static String getChatId(String uidA, String uidB) {
    final sorted = [uidA, uidB]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  DatabaseReference _messagesRef(String chatId) =>
      _rtdb.ref('messages/$chatId');

  // ── Chat creation ─────────────────────────────────────────────────────────

  Future<String> openOrCreateChat({required String otherUid}) async {
    final chatId = getChatId(_currentUid, otherUid);
    final chatRef = _db.collection('chats').doc(chatId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(chatRef);

      if (!snapshot.exists) {
        final now = Timestamp.now();
        transaction.set(chatRef, {
          'participants': [_currentUid, otherUid],
          'createdBy': _currentUid,
          'createdAt': now,
          'updatedAt': now,
          'lastMessage': '',
          'lastMessageType': '',
          'lastMessageSender': '',
        });
      }
    });

    return chatId;
  }

  // ── Chat list ─────────────────────────────────────────────────────────────

  Stream<List<Chat>> getUserChats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Chat.fromFirestore(d)).toList());
  }

  // ── Text messaging ────────────────────────────────────────────────────────

  /// Sends a text message.
  ///
  /// [recipientUid] — the other participant's UID, used to route the push
  /// notification. Pass [Chat.otherUid(currentUid)] from the calling widget.
  Future<void> sendTextMessage({
    required String chatId,
    required String content,
    required String recipientUid, // NEW — required for push notification
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Push message to RTDB
    final msgRef = _messagesRef(chatId).push();
    final messageId = msgRef.key!;

    await msgRef.set({
      'senderId': _currentUid,
      'type': 'text',
      'content': trimmed,
      'createdAt': now,
    });

    // 2. Update Firestore chat metadata
    await _db.collection('chats').doc(chatId).update({
      'lastMessage': trimmed,
      'lastMessageType': 'text',
      'lastMessageSender': _currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 3. Trigger push notification (fire-and-forget)
    unawaited(
      NotificationService.instance.sendChatNotification(
        chatId: chatId,
        recipientUid: recipientUid,
        messageId: messageId,
        messageType: 'text',
        content: trimmed,
      ),
    );
  }

  // ── Image messaging ───────────────────────────────────────────────────────

  /// Writes an already-uploaded image message to RTDB and updates Firestore.
  ///
  /// [recipientUid] — the other participant's UID.
  Future<void> sendImageMessage({
    required String chatId,
    required String messageId,
    required String imageUrl,
    required String recipientUid, // NEW — required for push notification
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _messagesRef(chatId).child(messageId).set({
      'senderId': _currentUid,
      'type': 'image',
      'content': imageUrl,
      'createdAt': now,
    });

    await _db.collection('chats').doc(chatId).update({
      'lastMessage': '📷 Photo',
      'lastMessageType': 'image',
      'lastMessageSender': _currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Fire-and-forget push notification
    unawaited(
      NotificationService.instance.sendChatNotification(
        chatId: chatId,
        recipientUid: recipientUid,
        messageId: messageId,
        messageType: 'image',
        content: '📷 Photo',
      ),
    );
  }

  // ── Audio messaging ───────────────────────────────────────────────────────

  /// Writes an already-uploaded audio message to RTDB and updates Firestore.
  ///
  /// [recipientUid] — the other participant's UID.
  Future<void> sendAudioMessage({
    required String chatId,
    required String messageId,
    required String audioUrl,
    required String recipientUid, // NEW — required for push notification
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    await _messagesRef(chatId).child(messageId).set({
      'senderId': _currentUid,
      'type': 'audio',
      'content': audioUrl,
      'createdAt': now,
    });

    await _db.collection('chats').doc(chatId).update({
      'lastMessage': '🎤 Voice message',
      'lastMessageType': 'audio',
      'lastMessageSender': _currentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Fire-and-forget push notification
    unawaited(
      NotificationService.instance.sendChatNotification(
        chatId: chatId,
        recipientUid: recipientUid,
        messageId: messageId,
        messageType: 'audio',
        content: '🎤 Voice message',
      ),
    );
  }

  // ── Pagination ────────────────────────────────────────────────────────────

  static const int _pageSize = 30;

  Future<List<ChatMessage>> loadInitialMessages(String chatId) async {
    final snap = await _messagesRef(
      chatId,
    ).orderByChild('createdAt').limitToLast(_pageSize).get();

    if (!snap.exists || snap.value == null) return [];
    return _snapshotToMessages(snap);
  }

  Future<List<ChatMessage>> loadOlderMessages({
    required String chatId,
    required int oldestTimestamp,
  }) async {
    final snap = await _messagesRef(chatId)
        .orderByChild('createdAt')
        .endAt(oldestTimestamp - 1)
        .limitToLast(_pageSize)
        .get();

    if (!snap.exists || snap.value == null) return [];
    return _snapshotToMessages(snap);
  }

  Stream<ChatMessage> listenForNewMessages({
    required String chatId,
    required int afterTimestamp,
  }) {
    return _messagesRef(chatId)
        .orderByChild('createdAt')
        .startAt(afterTimestamp + 1)
        .onChildAdded
        .map((event) {
          final data = Map<dynamic, dynamic>.from(
            event.snapshot.value as Map? ?? {},
          );
          return ChatMessage.fromRtdb(event.snapshot.key ?? '', data);
        });
  }

  List<ChatMessage> _snapshotToMessages(DataSnapshot snap) {
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    final messages = raw.entries.map((entry) {
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      return ChatMessage.fromRtdb(entry.key as String, data);
    }).toList();

    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }
}

// Suppress lint for intentional fire-and-forget calls.
void unawaited(Future<void> future) {}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/read_receipt_model.dart';

/// Manages read receipts via Firebase Realtime Database.
///
/// RTDB path: reads/{chatId}/{uid}
///   • lastReadTimestamp : int (Unix ms)
///
/// Update strategy — only write when:
///   1. Chat page opens (mark newest message read).
///   2. A new message arrives while the page is visible.
///   3. User navigates back to the chat page.
///
/// Do NOT update on every scroll event.
///
class ReadReceiptService {
  ReadReceiptService._();
  static final instance = ReadReceiptService._();

  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  DatabaseReference _receiptRef(String chatId, String uid) =>
      _rtdb.ref('reads/$chatId/$uid');

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Marks the chat as read up to [timestamp] for the current user.
  /// Only writes if [timestamp] is newer than what is already stored.

  Future<void> markRead({
    required String chatId,
    required int timestamp,
  }) async {
    final uid = _currentUid;
    if (uid == null || timestamp <= 0) return;

    final ref = _receiptRef(chatId, uid);

    // Transactional update: only advance forward, never go backwards.

    await ref.runTransaction((current) {
      final currentTs = (current as Map?)?['lastReadTimestamp'] as int? ?? 0;
      if (timestamp > currentTs) {
        return Transaction.success({'lastReadTimestamp': timestamp});
      }
      return Transaction.success(current);
    });
  }

  Future<ReadReceipt> getCurrentReceipt(String chatId) async {
    final uid = _currentUid;

    if (uid == null) {
      return ReadReceipt.empty(chatId, '');
    }

    final snap = await _receiptRef(chatId, uid).get();

    if (!snap.exists || snap.value == null) {
      return ReadReceipt.empty(chatId, uid);
    }

    final data = Map<dynamic, dynamic>.from(snap.value as Map);

    return ReadReceipt.fromRtdb(chatId, uid, data);
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  /// Streams the read receipt of [uid] in [chatId].

  Stream<ReadReceipt> watchReceipt({
    required String chatId,
    required String uid,
  }) {
    return _receiptRef(chatId, uid).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        return ReadReceipt.empty(chatId, uid);
      }
      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      return ReadReceipt.fromRtdb(chatId, uid, data);
    });
  }

  // ── Unread count ──────────────────────────────────────────────────────────

  /// Computes the unread count for [chatId] for the current user by
  /// comparing lastReadTimestamp against messages in RTDB.
  ///
  /// Does NOT read the full message list — queries only messages with
  /// createdAt > lastReadTimestamp that were NOT sent by the current user.

  Stream<int> watchUnreadCount({required String chatId}) async* {
    final uid = _currentUid;
    if (uid == null) {
      yield 0;
      return;
    }

    // First get our own read receipt as a one-shot to bootstrap.
    // Then react to receipt changes (when we mark read the count drops to 0).
    yield* _receiptRef(chatId, uid).onValue.asyncMap((event) async {
      final snap = event.snapshot;
      int lastRead = 0;
      if (snap.exists && snap.value != null) {
        final data = Map<dynamic, dynamic>.from(snap.value as Map);
        lastRead = data['lastReadTimestamp'] as int? ?? 0;
      }

      // Count messages after lastRead that weren't sent by us.
      final messagesSnap = await _rtdb
          .ref('messages/$chatId')
          .orderByChild('createdAt')
          .startAt(lastRead + 1)
          .get();

      if (!messagesSnap.exists || messagesSnap.value == null) return 0;

      final raw = Map<dynamic, dynamic>.from(messagesSnap.value as Map);
      int count = 0;
      for (final entry in raw.values) {
        final msg = Map<dynamic, dynamic>.from(entry as Map);
        if ((msg['senderId'] as String?) != uid) count++;
      }
      return count;
    });
  }
}

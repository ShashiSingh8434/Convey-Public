import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/typing_state_model.dart';

/// Manages typing indicators via Firebase Realtime Database.
///
/// RTDB path: typing/{chatId}/{uid}
///   • typing    : bool
///   • updatedAt : ServerValue.timestamp
///
/// Usage:
///   1. Call [onTextChanged] from the TextField's onChanged callback.
///   2. Call [clearTyping] on page dispose or app backgrounded.
class TypingService {
  TypingService._();
  static final instance = TypingService._();

  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  static const Duration _debounce = Duration(milliseconds: 1500);

  // Holds a debounce timer per chatId so multiple chats don't interfere.
  final Map<String, Timer> _timers = {};
  final Map<String, bool> _currentState = {};

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  DatabaseReference _typingRef(String chatId, String uid) =>
      _rtdb.ref('typing/$chatId/$uid');

  // ── Write helpers ─────────────────────────────────────────────────────────

  Future<void> _setTyping(String chatId, bool typing) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _typingRef(
      chatId,
      uid,
    ).update({'typing': typing, 'updatedAt': ServerValue.timestamp});
    _currentState[chatId] = typing;
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call whenever the text field value changes.
  void onTextChanged(String chatId, String text) {
    final isTyping = text.isNotEmpty;

    // Cancel previous debounce for this chat.
    _timers[chatId]?.cancel();

    if (isTyping) {
      // Only write true if we weren't already typing to minimise writes.
      if (_currentState[chatId] != true) {
        _setTyping(chatId, true);
      }

      // After inactivity, set typing = false.
      _timers[chatId] = Timer(_debounce, () {
        _setTyping(chatId, false);
        _timers.remove(chatId);
      });
    } else {
      // Text is empty — clear immediately.
      if (_currentState[chatId] != false) {
        _setTyping(chatId, false);
      }
    }
  }

  /// Call on page dispose or when the app backgrounds.
  Future<void> clearTyping(String chatId) async {
    _timers[chatId]?.cancel();
    _timers.remove(chatId);
    if (_currentState[chatId] == true) {
      await _setTyping(chatId, false);
    }
  }

  // ── Stream ────────────────────────────────────────────────────────────────

  /// Streams the typing state of [otherUid] in [chatId].
  /// Only listens to the OTHER participant's node.
  Stream<TypingState> watchTyping({
    required String chatId,
    required String otherUid,
  }) {
    return _typingRef(chatId, otherUid).onValue.map((event) {
      final snap = event.snapshot;

      if (!snap.exists || snap.value == null) {
        return TypingState.idle(chatId, otherUid);
      }

      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      final state = TypingState.fromRtdb(chatId, otherUid, data);

      // Safety fallback:
      // if typing flag is stale for more than 5 seconds,
      // consider the user not typing.
      if (state.isTyping) {
        final age = DateTime.now().difference(state.updatedAt);

        if (age.inSeconds > 5) {
          return TypingState.idle(chatId, otherUid);
        }
      }

      return state;
    });
  }
}

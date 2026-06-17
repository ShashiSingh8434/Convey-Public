// lib/core/notifications/notification_api_client.dart
//
// Thin HTTP wrapper around the Convey Communication Server.
//
// Architecture:
//   • All outbound notification requests go through this class.
//   • Auth token is always fetched fresh from Firebase (auto-refresh).
//   • Each method maps 1:1 to a server endpoint.
//   • Call methods are stubs — fully typed and wired, but the server
//     endpoints don't need to exist yet.
//
// To add a new notification type:
//   1. Add a method here.
//   2. Call it from NotificationService.
//   3. That's it — no other files change.

import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Configuration — replace with your real server base URL.
// Use a const so it can be swapped per build flavor easily.
// ─────────────────────────────────────────────────────────────────────────────

const _kBaseUrl = '*** update this with your connection server ***';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationApiClient
// ─────────────────────────────────────────────────────────────────────────────

class NotificationApiClient {
  NotificationApiClient._();
  static final instance = NotificationApiClient._();

  final _client = http.Client();

  // ── Auth header ────────────────────────────────────────────────────────────

  /// Always fetches a fresh Firebase ID token (cached by SDK for ~1 h).
  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not authenticated');

    final token = await user.getIdToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_kBaseUrl$path');
    final headers = await _headers();

    final response = await _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NotificationApiException(
        statusCode: response.statusCode,
        path: path,
        body: response.body,
      );
    }

    debugPrint('[NotificationApi] POST $path → ${response.statusCode}');
  }

  // ── Chat ───────────────────────────────────────────────────────────────────

  /// POST /api/v1/notifications/chat

  Future<void> sendChatNotification({
    required String chatId,
    required String recipientUid,
    required String messageId,
    required String messageType,
    required String content,
  }) async {
    await _post('/api/v1/notifications/chat', {
      'receiverId': recipientUid,
      'chatId': chatId,
      'messageId': messageId,
      'messageType': messageType,
      'content': content,
    });
  }
  // ── Calls ──────────────────────────────────────────────────────────────────

  /// POST /api/v1/notifications/call/incoming
  ///
  /// Sent by the caller after:
  /// 1. Creating RTDB call document
  /// 2. Creating SDP offer
  /// 3. Storing offer in RTDB
  Future<void> sendIncomingCallNotification({
    required String receiverId,
    required String chatId,
    required String callId,
    required String callType, // audio | video
  }) async {
    await _post('/api/v1/notifications/call/incoming', {
      'receiverId': receiverId,
      'chatId': chatId,
      'callId': callId,
      'callType': callType,
    });
  }

  /// POST /api/v1/notifications/call/accepted
  ///
  /// Sent by receiver after creating SDP answer.
  Future<void> sendCallAccepted({
    required String callerId,
    required String callId,
  }) async {
    await _post('/api/v1/notifications/call/accepted', {
      'callerId': callerId,
      'callId': callId,
    });
  }

  /// POST /api/v1/notifications/call/rejected
  Future<void> sendCallRejected({
    required String callerId,
    required String callId,
  }) async {
    await _post('/api/v1/notifications/call/rejected', {
      'callerId': callerId,
      'callId': callId,
    });
  }

  /// POST /api/v1/notifications/call/ended
  Future<void> sendCallEnded({
    required String targetId,
    required String callId,
  }) async {
    await _post('/api/v1/notifications/call/ended', {
      'targetId': targetId,
      'callId': callId,
    });
  }

  /// POST /api/v1/notifications/call/missed
  ///
  /// Called after 60 seconds if the receiver never answered.
  Future<void> sendMissedCall({
    required String receiverId,
    required String callId,
  }) async {
    await _post('/api/v1/notifications/call/missed', {
      'receiverId': receiverId,
      'callId': callId,
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────────────────────────────────────

class NotificationApiException implements Exception {
  final int statusCode;
  final String path;
  final String body;

  const NotificationApiException({
    required this.statusCode,
    required this.path,
    required this.body,
  });

  @override
  String toString() => 'NotificationApiException: $statusCode on $path — $body';
}

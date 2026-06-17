// lib/core/notifications/notification_service.dart
//
// Central notification coordinator for Convey.
//
// Responsibilities:
//   • FCM permission request & token lifecycle (register, refresh, remove)
//   • Foreground message display via flutter_local_notifications
//   • Background / terminated message routing (deep link on tap)
//   • Active-chat suppression (no toast when user is already in that chat)
//   • Dispatches to NotificationApiClient for outbound server calls
//   • Stubbed call-notification hooks for future WebRTC integration

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/router/app_router.dart';
import '../calls/models/call_model.dart';
import '../calls/providers/call_providers.dart';
import 'notification_api_client.dart';
import 'notification_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Top-level background handler — must be a top-level function (not a method).
// Called by FCM when a data-only message arrives while app is in background
// or terminated. Used today for future call-signal messages; chat notifications
// are displayed natively by FCM from their `notification` payload.
// ─────────────────────────────────────────────────────────────────────────────

// ------------------------------------------------------------------------------

// @pragma('vm:entry-point')
// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   final plugin = FlutterLocalNotificationsPlugin();

//   const android = AndroidNotificationDetails(
//     'convey_chat',
//     'Chat messages',
//     importance: Importance.high,
//     priority: Priority.high,
//   );

//   await plugin.show(
//     message.hashCode,
//     message.data['displayName'] ?? 'Convey',
//     message.data['body'] ?? 'New message',
//     const NotificationDetails(android: android),
//   );
// }

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();

  final type = NotificationType.fromString(message.data['type']);
  final title =
      message.data['senderName'] ?? message.data['displayName'] ?? 'Convey';
  final body =
      message.data['body'] as String? ??
      (type == NotificationType.incomingCall
          ? 'Incoming ${message.data['callType'] == 'video' ? 'video' : 'audio'} call'
          : type == NotificationType.callBusy
          ? 'Call busy'
          : type == NotificationType.callRejected
          ? 'Call rejected'
          : type == NotificationType.callEnded
          ? 'Call ended'
          : type == NotificationType.missedCall
          ? 'Missed call'
          : 'New message');
  final channelId = type == NotificationType.chat
      ? _kChatChannelId
      : type == NotificationType.incomingCall
      ? _kCallChannelId
      : (type == NotificationType.callBusy ||
            type == NotificationType.callRejected ||
            type == NotificationType.callEnded)
      ? _kCallStateChannelId
      : type == NotificationType.missedCall
      ? _kMissedCallChannelId
      : _kChatChannelId;

  await plugin.show(
    message.hashCode,

    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Convey',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification type enum — drives routing for both inbound and outbound.
// Extend here when WebRTC call notifications are added.
// ─────────────────────────────────────────────────────────────────────────────

enum NotificationType {
  chat,

  incomingCall,
  callAccepted,
  callRejected,
  callEnded,

  callBusy,
  missedCall,

  unknown;

  static NotificationType fromString(String? value) => switch (value) {
    'chat' => chat,

    'incoming_call' => incomingCall,
    'call_accepted' => callAccepted,
    'call_rejected' => callRejected,
    'call_ended' => callEnded,

    'call_busy' => callBusy,
    'missed_call' => missedCall,

    _ => unknown,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Android notification channel
// ─────────────────────────────────────────────────────────────────────────────

const _kChatChannelId = 'convey_chat';
const _kChatChannelName = 'Chat messages';
const _kChatChannelDesc = 'Incoming chat messages from friends';

const _kCallChannelId = 'convey_calls';
const _kCallChannelName = 'Calls';
const _kCallChannelDesc = 'Incoming call alerts';

const _kCallStateChannelId = 'convey_call_state';
const _kCallStateChannelName = 'Call Updates';
const _kCallStateChannelDesc = 'Accepted, rejected, busy and ended call events';

const _kMissedCallChannelId = 'convey_missed';
const _kMissedCallChannelName = 'Missed Calls';
const _kMissedCallChannelDesc = 'Missed call notifications';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationService
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();
  final _db = FirebaseFirestore.instance;

  // Kept nullable — set by initialize() once a ProviderContainer is available.
  ProviderContainer? _container;

  /// Must be called once, after Firebase.initializeApp(), before runApp().
  /// [container] is the root ProviderScope container so we can read providers
  /// from outside the widget tree (e.g. in background handlers).
  Future<void> initialize(ProviderContainer container) async {
    _container = container;

    await _requestPermission();
    await _initLocalNotifications();
    await _registerToken();
    _listenTokenRefresh();
    _listenForegroundMessages();
    _listenNotificationTaps();
    await _handleTerminatedLaunch();
  }

  /// Public entry point for token registration.
  /// Called by fcmTokenSyncProvider on auth state change.
  Future<void> registerToken() => _registerToken();

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  // ── Local notifications setup ──────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_notification',
    );
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    // Create Android channels
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kChatChannelId,
        _kChatChannelName,
        description: _kChatChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kCallChannelId,
        _kCallChannelName,
        description: _kCallChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kCallStateChannelId,
        _kCallStateChannelName,
        description: _kCallStateChannelDesc,
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kMissedCallChannelId,
        _kMissedCallChannelName,
        description: _kMissedCallChannelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );
  }

  // ── Token management ───────────────────────────────────────────────────────

  Future<void> _registerToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // APNS token must be fetched first on iOS, otherwise getToken() can return null.
    if (Platform.isIOS) {
      await _fcm.getAPNSToken();
    }

    final token = await _fcm.getToken();
    if (token == null) return;

    await _saveToken(uid: uid, token: token);
  }

  void _listenTokenRefresh() {
    _fcm.onTokenRefresh.listen((newToken) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await _saveToken(uid: uid, token: newToken);
    });
  }

  /// Saves the token to Firestore under users/{uid}.fcmTokens.
  /// Uses arrayUnion with a structured object so each device is tracked.
  /// Duplicate tokens are prevented by removing the old entry for this
  /// deviceId first (via a transaction).
  Future<void> _saveToken({required String uid, required String token}) async {
    final platform = Platform.isAndroid ? 'android' : 'ios';
    // Stable device identifier: hash of first 16 chars of the token.
    // Avoids adding `device_info_plus` as a dependency.
    final deviceId = _stableDeviceId(token);

    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final existing = List<Map<String, dynamic>>.from(
        (data['fcmTokens'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      // Remove any entry for this deviceId (token rotation or reinstall).
      existing.removeWhere((t) => t['deviceId'] == deviceId);

      existing.add({
        'token': token,
        'platform': platform,
        'deviceId': deviceId,
        'updatedAt': Timestamp.now(),
      });

      tx.update(userRef, {'fcmTokens': existing});
    });
  }

  /// Removes the current device's token from Firestore. Called on logout.
  Future<void> removeCurrentToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final token = await _fcm.getToken();
    if (token == null) return;

    final deviceId = _stableDeviceId(token);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      if (!snap.exists) return;

      final data = snap.data() ?? {};
      final existing = List<Map<String, dynamic>>.from(
        (data['fcmTokens'] as List<dynamic>? ?? []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );

      existing.removeWhere((t) => t['deviceId'] == deviceId);
      tx.update(userRef, {'fcmTokens': existing});
    });
  }

  String _stableDeviceId(String token) {
    // Deterministic 16-char id from the token — no extra package needed.
    final bytes = utf8.encode(token.substring(0, token.length.clamp(0, 32)));
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, 16);
  }

  // ── Foreground message handling ────────────────────────────────────────────

  void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((message) async {
      final type = NotificationType.fromString(message.data['type']);

      switch (type) {
        case NotificationType.chat:
          await _handleForegroundChatMessage(message);
          break;
        case NotificationType.incomingCall:
          _handleIncomingCallData(message.data);
          break;
        case NotificationType.callAccepted:
          debugPrint('[FCM] call_accepted received: ${message.data}');
          break;
        case NotificationType.callRejected:
          _handleCallUpdate(CallStatus.rejected);
          break;
        case NotificationType.callEnded:
          _handleCallUpdate(CallStatus.ended);
          break;
        case NotificationType.callBusy:
          _handleCallUpdate(CallStatus.busy);
          break;
        case NotificationType.missedCall:
          _handleCallUpdate(CallStatus.timeout);
          break;
        case NotificationType.unknown:
          debugPrint('[FCM] Unknown notification type: ${message.data}');
          break;
      }
    });
  }

  Future<String?> _downloadNotificationImage(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/notification_avatar.jpg');

      await file.writeAsBytes(response.bodyBytes);

      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleForegroundChatMessage(RemoteMessage message) async {
    final chatId = message.data['chatId'] as String?;
    if (chatId == null) return;

    final activeChatId = _container?.read(activeChatProvider);
    if (activeChatId == chatId) return;

    final notification = message.notification;

    final title =
        notification?.title ?? message.data['displayName'] ?? 'Convey';

    final body = notification?.body ?? message.data['body'] ?? 'New message';

    final photoUrl = message.data['photoUrl'];

    String? avatarPath;

    if (photoUrl != null && photoUrl.isNotEmpty) {
      avatarPath = await _downloadNotificationImage(photoUrl);
    }

    final payload = jsonEncode({
      'type': 'chat',
      'chatId': chatId,
      'displayName': message.data['displayName'] ?? title,
      'photoUrl': photoUrl,
      'otherUid': message.data['senderUid'] ?? '',
    });

    await _local.show(
      chatId.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _kChatChannelId,
          _kChatChannelName,
          channelDescription: _kChatChannelDesc,
          importance: Importance.high,
          priority: Priority.high,

          largeIcon: avatarPath != null
              ? FilePathAndroidBitmap(avatarPath)
              : null,

          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }
  // ── Notification tap handling ──────────────────────────────────────────────

  /// Registers FCM background tap listener (app was in background).
  void _listenNotificationTaps() {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  /// Checks if the app was launched from a terminated state via a notification.
  Future<void> _handleTerminatedLaunch() async {
    final message = await _fcm.getInitialMessage();
    if (message != null) {
      // Delay to allow widget tree to be built before navigating.
      await Future.delayed(const Duration(milliseconds: 500));
      _handleMessage(message);
    }
  }

  /// Routes an FCM RemoteMessage tap to the correct in-app screen.
  void _handleMessage(RemoteMessage message) {
    final type = NotificationType.fromString(message.data['type']);

    switch (type) {
      case NotificationType.chat:
        _navigateToChat(message.data);
        break;
      case NotificationType.incomingCall:
        _handleIncomingCallData(message.data);
        break;
      case NotificationType.callAccepted:
        debugPrint('[FCM] call_accepted tap: ${message.data}');
        break;
      case NotificationType.callRejected:
        _handleCallUpdate(CallStatus.rejected);
        break;
      case NotificationType.callEnded:
        _handleCallUpdate(CallStatus.ended);
        break;
      case NotificationType.callBusy:
        _handleCallUpdate(CallStatus.busy);
        break;
      case NotificationType.missedCall:
        _handleCallUpdate(CallStatus.timeout);
        break;
      case NotificationType.unknown:
        break;
    }
  }

  void _handleIncomingCallData(Map<String, dynamic> data) {
    final callId = data['callId'] as String?;
    final callerUid = data['senderId'] as String?;
    final callerName = data['senderName'] as String? ?? 'Unknown';
    final callerPhotoUrl = data['senderPhotoUrl'] as String?;
    final chatId = data['chatId'] as String?;
    final callType = (data['callType'] as String?) == 'video'
        ? CallType.video
        : CallType.audio;

    if (callId == null || callerUid == null || chatId == null) return;

    _container
        ?.read(callStateProvider.notifier)
        .setIncomingCall(
          callId: callId,
          callerUid: callerUid,
          callerName: callerName,
          callerPhotoUrl: callerPhotoUrl,
          chatId: chatId,
          callType: callType,
        );

    AppRouter.router.go('/incoming-call');
  }

  void _handleCallUpdate(CallStatus status) {
    _container?.read(callStateProvider.notifier).handleRemoteCallEvent(status);
  }

  /// Tap on a local notification shown in foreground.
  void _onLocalNotificationTap(NotificationResponse response) {
    final payloadStr = response.payload;
    if (payloadStr == null) return;

    try {
      final data = jsonDecode(payloadStr) as Map<String, dynamic>;
      final type = NotificationType.fromString(data['type'] as String?);

      if (type == NotificationType.chat) {
        _navigateToChat(data);
      }
      // TODO(calls): handle call taps
    } catch (e) {
      debugPrint('[FCM] Failed to parse local notification payload: $e');
    }
  }

  void _navigateToChat(Map<String, dynamic> data) {
    final chatId = data['chatId'] as String?;
    if (chatId == null) return;

    AppRouter.router.go(
      '/chat/$chatId',
      extra: {
        'displayName': data['displayName'] as String? ?? 'Chat',
        'photoUrl': data['photoUrl'] as String?,
        'otherUid':
            data['otherUid'] as String? ?? data['senderUid'] as String? ?? '',
      },
    );
  }

  // ── Outbound: Chat notification ────────────────────────────────────────────

  /// Call this after a message has been written to RTDB   Firestore.
  /// Fire-and-forget — errors are logged but never bubble up to the caller.
  Future<void> sendChatNotification({
    required String chatId,
    required String recipientUid,
    required String messageId,
    required String messageType, // 'text' | 'image' | 'audio'
    required String content,
  }) async {
    try {
      final sender = FirebaseAuth.instance.currentUser;
      if (sender == null) return;

      await NotificationApiClient.instance.sendChatNotification(
        chatId: chatId,
        recipientUid: recipientUid,
        messageId: messageId,
        messageType: messageType,
        content: content,
      );
    } catch (e) {
      debugPrint('[NotificationService] sendChatNotification failed: $e');
    }
  }

  // ── Outbound: Call notifications (stubs for WebRTC) ───────────────────────

  /// Send a call invite. Implement when WebRTC is ready.
  Future<void> sendIncomingCallNotification({
    required String receiverId,
    required String chatId,
    required String callId,
    required String callType,
  }) async {
    try {
      final sender = FirebaseAuth.instance.currentUser;
      if (sender == null) return;
      await NotificationApiClient.instance.sendIncomingCallNotification(
        callId: callId,
        callType: callType,
        receiverId: receiverId,
        chatId: chatId,
      );
    } catch (e) {
      debugPrint('[NotificationService] sendCallInvite failed: $e');
    }
  }

  Future<void> sendCallAccepted({
    required String callerId,
    required String callId,
  }) async {
    try {
      await NotificationApiClient.instance.sendCallAccepted(
        callId: callId,
        callerId: callerId,
      );
    } catch (e) {
      debugPrint('[NotificationService] acceptCall failed: $e');
    }
  }

  Future<void> sendCallRejected({
    required String callerId,
    required String callId,
  }) async {
    try {
      await NotificationApiClient.instance.sendCallRejected(
        callId: callId,
        callerId: callerId,
      );
    } catch (e) {
      debugPrint('[NotificationService] rejectCall failed: $e');
    }
  }

  Future<void> sendCallEnded({
    required String targetId,
    required String callId,
  }) async {
    try {
      await NotificationApiClient.instance.sendCallEnded(
        callId: callId,
        targetId: targetId,
      );
    } catch (e) {
      debugPrint('[NotificationService] endCall failed: $e');
    }
  }

  Future<void> sendMissedCall({
    required String receiverId,
    required String callId,
  }) async {
    try {
      await NotificationApiClient.instance.sendMissedCall(
        callId: callId,
        receiverId: receiverId,
      );
    } catch (e) {
      debugPrint('[NotificationService] missed call failed: $e');
    }
  }
}

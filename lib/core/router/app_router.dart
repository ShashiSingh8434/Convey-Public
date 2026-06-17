import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/pages/auth_gate.dart';
import '../../features/chats/pages/chat_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/friends/pages/discover_users_page.dart';
import '../../features/friends/pages/friend_requests_page.dart';
import '../../features/friends/pages/friend_profile_page.dart';
import '../../features/friends/pages/friends_page.dart';
import '../../features/onboarding/pages/profile_setup_page.dart';
import '../../features/onboarding/pages/username_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/calls/pages/incoming_call_page.dart';
import '../../features/calls/pages/outgoing_call_page.dart';
import '../../features/calls/pages/audio_call_page.dart';
import '../../features/calls/pages/video_call_page.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',

    refreshListenable: GoRouterRefreshStream(
      FirebaseAuth.instance.authStateChanges(),
    ),

    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (state.matchedLocation != '/') {
          return '/';
        }
      }

      return null;
    },

    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGate()),

      GoRoute(
        path: '/onboarding/username',
        builder: (context, state) => const UsernamePage(),
      ),

      GoRoute(
        path: '/onboarding/profile',
        builder: (context, state) => const ProfileSetupPage(),
      ),

      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardPage(),
      ),

      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),

      // ── Friend system routes ──────────────────────────────────────────────
      GoRoute(
        path: '/discover',
        builder: (context, state) => const DiscoverUsersPage(),
      ),

      GoRoute(
        path: '/friend-requests',
        builder: (context, state) => const FriendRequestsPage(),
      ),

      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsPage(),
      ),

      GoRoute(
        path: '/friends/:uid/profile',
        builder: (context, state) =>
            FriendProfilePage(friendUid: state.pathParameters['uid']!),
      ),

      // ── Chat routes ───────────────────────────────────────────────────────

      /// Dynamic chat screen.
      /// Expects [extra] map with keys: displayName, photoUrl, otherUid.
      GoRoute(
        path: '/chat/:chatId',
        builder: (context, state) {
          final chatId = state.pathParameters['chatId']!;
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return ChatPage(
            chatId: chatId,
            displayName: extra['displayName'] as String? ?? 'Chat',
            photoUrl: extra['photoUrl'] as String?,
            otherUid: extra['otherUid'] as String? ?? '',
          );
        },
      ),

      // ── Calls ───────────────────────────────────────────────────────
      GoRoute(
        path: '/incoming-call',
        builder: (context, state) => const IncomingCallPage(),
      ),
      GoRoute(
        path: '/outgoing-call',
        builder: (context, state) => const OutgoingCallPage(),
      ),

      GoRoute(
        path: '/audio-call',
        builder: (context, state) => const AudioCallPage(),
      ),

      GoRoute(
        path: '/video-call',
        builder: (context, state) => const VideoCallPage(),
      ),
    ],
  );
}

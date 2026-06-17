import 'package:convey/features/chats/providers/chat_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../auth/services/auth_service.dart';
import '../chats/pages/start_chat_dialog.dart';
import '../chats/widgets/chat_list_tile.dart';
import '../friends/providers/friends_providers.dart';
import '../profile/widgets/profile_avatar.dart';

Future<void> _logout(BuildContext context, WidgetRef ref) async {
  try {
    // Clear cached providers
    ref.invalidate(userDocumentProvider);
    ref.invalidate(userChatsProvider);
    ref.invalidate(pendingRequestCountProvider);

    await AuthService.instance.signOut();

    if (context.mounted) {
      context.go('/');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to logout: $e')));
    }
  }
}

Future<void> _showLogoutDialog(BuildContext context, WidgetRef ref) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return Dialog(
        backgroundColor: const Color(0xFF151B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                  size: 34,
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Are you sure you want to logout from Convey?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),

              const SizedBox(height: 28),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  if (shouldLogout == true && context.mounted) {
    await _logout(context, ref);
  }
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userDocumentProvider);
    final pendingCount = ref.watch(pendingRequestCountProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        elevation: 0,
        title: const Text(
          'Convey',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(userDocumentProvider);
              ref.refresh(userChatsProvider);
              ref.invalidate(unreadCountProvider);
              ref.invalidate(readReceiptProvider);
              ref.invalidate(pendingRequestCountProvider);
            },
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: Colors.white10, height: 1),
        ),
      ),
      drawer: userAsync.when(
        data: (user) => _AppDrawer(
          displayName: user?.profile.displayName ?? user?.username ?? 'User',
          username: user?.username ?? '',
          photoUrl: user?.profile.photoUrl,
          pendingRequestCount: pendingCount,
          onProfileTap: () {
            Navigator.of(context).pop();
            context.push('/profile');
          },
          onDiscoverTap: () {
            Navigator.of(context).pop();
            context.push('/discover');
          },
          onFriendRequestsTap: () {
            Navigator.of(context).pop();
            context.push('/friend-requests');
          },
          onFriendsTap: () {
            Navigator.of(context).pop();
            context.push('/friends');
          },
          onLogoutTap: () => _showLogoutDialog(context, ref),
        ),
        loading: () => const Drawer(),
        error: (_, _) => const Drawer(),
      ),
      body: const ChatListPage(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showStartChatDialog(context),
        tooltip: 'Start Chat',
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAWER (unchanged from original, kept here for completeness)
// ─────────────────────────────────────────────────────────────────────────────

class _AppDrawer extends StatelessWidget {
  final String displayName;
  final String username;
  final String? photoUrl;
  final int pendingRequestCount;
  final VoidCallback onProfileTap;
  final VoidCallback onDiscoverTap;
  final VoidCallback onFriendRequestsTap;
  final VoidCallback onFriendsTap;
  final VoidCallback onLogoutTap;

  const _AppDrawer({
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.pendingRequestCount,
    required this.onProfileTap,
    required this.onDiscoverTap,
    required this.onFriendRequestsTap,
    required this.onFriendsTap,
    required this.onLogoutTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Drawer(
      backgroundColor: const Color(0xFF0B0F17),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileAvatar(
                    photoUrl: photoUrl,
                    displayName: displayName,
                    radius: 22,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '@$username',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerItem(
                    icon: Icons.person_outline_rounded,
                    label: 'My Profile',
                    onTap: onProfileTap,
                  ),
                  const _DrawerDivider(label: 'People'),
                  _DrawerItem(
                    icon: Icons.explore_outlined,
                    label: 'Discover People',
                    onTap: onDiscoverTap,
                  ),
                  _DrawerItem(
                    icon: Icons.person_add_outlined,
                    label: 'Friend Requests',
                    badge: pendingRequestCount,
                    onTap: onFriendRequestsTap,
                  ),
                  _DrawerItem(
                    icon: Icons.people_outline_rounded,
                    label: 'My Friends',
                    onTap: onFriendsTap,
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'Logout',
                    onTap: onLogoutTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerDivider extends StatelessWidget {
  final String label;
  const _DrawerDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white24,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: badge > 0
          ? Badge(
              label: Text('$badge'),
              child: Icon(icon, color: Colors.white70),
            )
          : Icon(icon, color: Colors.white70),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

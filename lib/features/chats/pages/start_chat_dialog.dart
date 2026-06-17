import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../friends/providers/friends_providers.dart';
import '../../onboarding/models/user_model.dart';
import '../../profile/widgets/profile_avatar.dart';
import '../services/chat_service.dart';

Future<void> showStartChatDialog(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StartChatSheet(),
  );
}

class _StartChatSheet extends ConsumerWidget {
  const _StartChatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendUsersAsync = ref.watch(friendUsersProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F17),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle ──
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Text(
                  'Start Chat',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'Start chatting with your friends',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ),
              const Divider(color: Colors.white10, height: 1),
              // ── Friend list ──
              Expanded(
                child: friendUsersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text(
                      'Could not load friends.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  data: (friends) {
                    if (friends.isEmpty) {
                      return _EmptyFriendsState();
                    }
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        return _FriendTile(
                          user: friends[index],
                          onTap: () async {
                            Navigator.of(context).pop();
                            await _openOrCreateChat(
                              context: context,
                              friend: friends[index],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openOrCreateChat({
    required BuildContext context,
    required AppUser friend,
  }) async {
    try {
      final chatId = await ChatService.instance.openOrCreateChat(
        otherUid: friend.uid,
      );
      if (context.mounted) {
        context.push(
          '/chat/$chatId',
          extra: {
            'displayName':
                friend.profile.displayName ?? friend.username ?? 'User',
            'photoUrl': friend.profile.photoUrl,
            'otherUid': friend.uid,
          },
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open chat. Try again.')),
        );
      }
    }
  }
}

class _FriendTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;

  const _FriendTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final displayName =
        user.profile.displayName ?? user.username ?? 'Unknown User';
    final username = user.username ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: ProfileAvatar(
        photoUrl: user.profile.photoUrl,
        displayName: displayName,
        radius: 22,
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: username.isNotEmpty
          ? Text(
              '@$username',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _EmptyFriendsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            const Text(
              'No friends yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add some friends first to start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/discover');
              },
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Discover People'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

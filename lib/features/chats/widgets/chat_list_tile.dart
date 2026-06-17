import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_model.dart';
import '../pages/chat_list_page.dart';
import '../providers/chat_providers.dart';

class ChatListPage extends ConsumerWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(userChatsProvider);

    return chatsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(
        child: Text(
          'Could not load chats.',
          style: TextStyle(color: Colors.white54),
        ),
      ),
      data: (chats) {
        if (chats.isEmpty) {
          return _EmptyChatsState();
        }
        return ListView.separated(
          itemCount: chats.length,
          separatorBuilder: (_, _) =>
              const Divider(color: Colors.white10, height: 1, indent: 72),
          itemBuilder: (context, index) {
            return _ChatTileLoader(chat: chats[index]);
          },
        );
      },
    );
  }
}

// Loads the other participant's user doc before rendering the tile
class _ChatTileLoader extends ConsumerWidget {
  final Chat chat;
  const _ChatTileLoader({required this.chat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participantAsync = ref.watch(chatParticipantProvider(chat.id));

    return participantAsync.when(
      loading: () => const _ShimmerChatTile(),
      error: (_, _) => const SizedBox.shrink(),
      data: (user) {
        if (user == null) return const SizedBox.shrink();
        final presenceAsync = ref.watch(presenceProvider(user.uid));
        final unreadAsync = ref.watch(unreadCountProvider(chat.id));
        final unreadCount = unreadAsync.value ?? 0;
        return ChatListTile(
          chat: chat,
          otherUser: user,
          isOnline: presenceAsync.value?.online ?? false,
          unreadCount: unreadCount,
          onTap: () => context.push(
            '/chat/${chat.id}',
            extra: {
              'displayName':
                  user.profile.displayName ?? user.username ?? 'User',
              'photoUrl': user.profile.photoUrl,
              'otherUid': user.uid,
            },
          ),
        );
      },
    );
  }
}

class _ShimmerChatTile extends StatelessWidget {
  const _ShimmerChatTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const CircleAvatar(radius: 26, backgroundColor: Colors.white10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 12,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChatsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the button below to start chatting with a friend.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

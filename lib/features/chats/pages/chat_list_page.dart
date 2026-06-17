import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../onboarding/models/user_model.dart';
import '../../profile/widgets/profile_avatar.dart';
import '../models/chat_model.dart';

class ChatListTile extends StatelessWidget {
  final Chat chat;
  final bool isOnline;
  final AppUser otherUser;
  final VoidCallback onTap;
  final int unreadCount;

  const ChatListTile({
    super.key,
    required this.onTap,
    required this.chat,
    required this.isOnline,
    required this.otherUser,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final displayName =
        otherUser.profile.displayName ?? otherUser.username ?? 'User';
    final lastMsg = chat.lastMessage;
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMyMessage =
        chat.lastMessageSender != null && chat.lastMessageSender == currentUid;

    final timeLabel = _formatTime(chat.updatedAt);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAvatar(
                  photoUrl: otherUser.profile.photoUrl,
                  displayName: displayName,
                  radius: 26,
                ),

                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF0B0F17),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeLabel,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              fontSize: 12,
                            ),
                          ),

                          const SizedBox(height: 4),

                          if (unreadCount > 0)
                            Container(
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                unreadCount > 99
                                    ? '99+'
                                    : unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (lastMsg != null)
                    Text(
                      isMyMessage ? 'You: $lastMsg' : lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    )
                  else
                    const Text(
                      'Say hello 👋',
                      style: TextStyle(
                        color: Colors.white24,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year % 100}';
  }
}

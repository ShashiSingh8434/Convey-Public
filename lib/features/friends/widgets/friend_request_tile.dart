import 'package:flutter/material.dart';

import '../../../features/onboarding/models/user_model.dart';
import '../../../features/profile/widgets/profile_avatar.dart';
import '../models/friend_request_model.dart';

// ── Received Request Tile ─────────────────────────────────────────────────

class ReceivedRequestTile extends StatelessWidget {
  final FriendRequest request;
  final AppUser? fromUser;
  final bool loading;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const ReceivedRequestTile({
    super.key,
    required this.request,
    required this.fromUser,
    required this.loading,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName =
        fromUser?.profile.displayName ?? fromUser?.username ?? '…';
    final username = fromUser?.username ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  photoUrl: fromUser?.profile.photoUrl,
                  displayName: displayName,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (username.isNotEmpty)
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.8,
                            ),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (request.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  request.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: loading ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: loading ? null : onAccept,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: loading
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sent Request Tile ─────────────────────────────────────────────────────

class SentRequestTile extends StatelessWidget {
  final FriendRequest request;
  final AppUser? toUser;
  final bool loading;
  final VoidCallback onWithdraw;

  const SentRequestTile({
    super.key,
    required this.request,
    required this.toUser,
    required this.loading,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = toUser?.profile.displayName ?? toUser?.username ?? '…';
    final username = toUser?.username ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(
                  photoUrl: toUser?.profile.photoUrl,
                  displayName: displayName,
                  radius: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (username.isNotEmpty)
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.8,
                            ),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: loading ? null : onWithdraw,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.redAccent,
                          ),
                        )
                      : const Text('Withdraw', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            if (request.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  request.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

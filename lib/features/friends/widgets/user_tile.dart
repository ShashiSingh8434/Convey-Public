import 'package:flutter/material.dart';

import '../../../features/onboarding/models/user_model.dart';
import '../../profile/widgets/profile_avatar.dart';

class UserTile extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;

  const UserTile({super.key, required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = user.profile.displayName ?? user.username ?? 'Unknown';
    final username = user.username ?? '';

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ProfileAvatar(
        photoUrl: user.profile.photoUrl,
        displayName: displayName,
        radius: 24,
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        '@$username',
        style: TextStyle(
          color: theme.colorScheme.primary.withValues(alpha: 0.8),
          fontSize: 13,
        ),
      ),
    );
  }
}

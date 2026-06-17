import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/loading_screen.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../onboarding/models/user_model.dart';
import '../../profile/widgets/profile_avatar.dart';
import '../../profile/widgets/social_link_tile.dart';
import '../services/friend_service.dart';

class FriendProfilePage extends ConsumerStatefulWidget {
  final String friendUid;

  const FriendProfilePage({super.key, required this.friendUid});

  @override
  ConsumerState<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends ConsumerState<FriendProfilePage> {
  AppUser? _user;
  bool _loading = true;
  bool _isFriend = false;
  bool _removing = false;

  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      // Validate friendship before rendering any data
      final areFriends = await FriendService.instance.areFriends(
        _currentUid,
        widget.friendUid,
      );

      if (!areFriends) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.friendUid)
          .get();

      if (mounted) {
        setState(() {
          _user = snap.exists ? AppUser.fromFirestore(snap) : null;
          _isFriend = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, e.toString());
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmAndRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2030),
        title: const Text(
          'Remove Friend',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove @${_user?.username ?? ''} from your friends?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _removing = true);
    try {
      await FriendService.instance.removeFriend(
        currentUid: _currentUid,
        otherUid: widget.friendUid,
      );
      if (mounted) {
        AppSnackbar.success(context, 'Friend removed.');
        context.pop();
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_loading) return const AppLoadingScreen();

    // Access denied if not friends
    if (!_isFriend) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0F17),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: Colors.white24, size: 48),
              SizedBox(height: 12),
              Text(
                'This profile is only visible to friends.',
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B0F17),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0F17),
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text(
            'User not found.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final user = _user!;
    final hasSocial = (user.social.github?.isNotEmpty == true) ||
        (user.social.instagram?.isNotEmpty == true) ||
        (user.social.linkedin?.isNotEmpty == true);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        foregroundColor: Colors.white,
        title: Text('@${user.username ?? ''}'),
        actions: [
          IconButton(
            onPressed: _removing ? null : _confirmAndRemove,
            icon: _removing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : const Icon(Icons.person_remove_outlined, color: Colors.white70),
            tooltip: 'Remove Friend',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              children: [
                const SizedBox(height: 8),

                // ── Avatar ──
                ProfileAvatar(
                  photoUrl: user.profile.photoUrl,
                  displayName: user.profile.displayName,
                  radius: 56,
                ),

                const SizedBox(height: 20),

                // ── Username ──
                Text(
                  '@${user.username ?? ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 8),

                // ── Display name ──
                Text(
                  user.profile.displayName ?? '',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // ── About ──
                if (user.profile.about?.isNotEmpty == true) ...[
                  const SizedBox(height: 20),
                  _SectionLabel('About'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2030),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      user.profile.about!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Social ──
                _SectionLabel('Social Links'),
                const SizedBox(height: 12),

                if (!hasSocial)
                  const Text(
                    'No social links added.',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  )
                else ...[
                  SocialLinkTile(
                    icon: Icons.code,
                    label: 'GitHub',
                    username: user.social.github,
                    urlPrefix: 'https://github.com/',
                  ),
                  SocialLinkTile(
                    icon: Icons.camera_alt_outlined,
                    label: 'Instagram',
                    username: user.social.instagram,
                    urlPrefix: 'https://instagram.com/',
                  ),
                  SocialLinkTile(
                    icon: Icons.work_outline,
                    label: 'LinkedIn',
                    username: user.social.linkedin,
                    urlPrefix: 'https://linkedin.com/in/',
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    ),
  );
}

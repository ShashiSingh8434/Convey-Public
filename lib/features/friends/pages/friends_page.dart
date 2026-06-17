import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/snackbar.dart';
import '../../onboarding/models/user_model.dart';
import '../providers/friends_providers.dart';
import '../services/friend_service.dart';
import '../widgets/friend_tile.dart';

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  final _searchController = TextEditingController();
  String _filterQuery = '';
  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _filterQuery = _searchController.text.toLowerCase().trim(),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppUser> _applyFilter(List<AppUser> users) {
    if (_filterQuery.isEmpty) return users;
    return users.where((u) {
      final username = (u.username ?? '').toLowerCase();
      final displayName = (u.profile.displayName ?? '').toLowerCase();
      return username.contains(_filterQuery) ||
          displayName.contains(_filterQuery);
    }).toList();
  }

  Future<void> _confirmAndRemoveFriend(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2030),
        title: const Text(
          'Remove Friend',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Remove @${user.username ?? ''} from your friends?',
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

    try {
      await FriendService.instance.removeFriend(
        currentUid: _currentUid,
        otherUid: user.uid,
      );
      if (mounted) AppSnackbar.success(context, 'Friend removed.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final friendUsersAsync = ref.watch(friendUsersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        foregroundColor: Colors.white,
        title: const Text('My Friends'),
      ),
      body: friendUsersAsync.when(
        data: (allUsers) {
          final users = _applyFilter(allUsers);
          return Column(
            children: [
              // ── Local search bar ──
              if (allUsers.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search friends…',
                      hintStyle: const TextStyle(color: Colors.white30),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white38,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white38,
                              ),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1A2030),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                    ),
                  ),
                ),

              // ── List ──
              Expanded(
                child: users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.people_outline,
                              color: Colors.white24,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _filterQuery.isNotEmpty
                                  ? 'No friends match your search.'
                                  : 'No friends yet.\nDiscover people to connect with!',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return Dismissible(
                            key: ValueKey(user.uid),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              await _confirmAndRemoveFriend(user);
                              // Return false — the provider stream removes the
                              // tile automatically once Firestore updates.
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red.withValues(alpha: 0.2),
                              child: const Icon(
                                Icons.person_remove_outlined,
                                color: Colors.redAccent,
                              ),
                            ),
                            child: FriendTile(
                              user: user,
                              onTap: () =>
                                  context.push('/friends/${user.uid}/profile'),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Text(
            e.toString(),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ),
    );
  }
}

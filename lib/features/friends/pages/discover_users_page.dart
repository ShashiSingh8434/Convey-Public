import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/loading_screen.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../onboarding/models/user_model.dart';
import '../models/relationship_status.dart';
import '../services/friend_service.dart';
import '../widgets/user_tile.dart';

class DiscoverUsersPage extends ConsumerStatefulWidget {
  const DiscoverUsersPage({super.key});

  @override
  ConsumerState<DiscoverUsersPage> createState() => _DiscoverUsersPageState();
}

class _DiscoverUsersPageState extends ConsumerState<DiscoverUsersPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;

  List<AppUser> _users = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  bool _searching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadNextPage();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore &&
        !_searching) {
      _loadNextPage();
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    _searchQuery = query;

    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _users = [];
        _lastDoc = null;
        _hasMore = true;
      });
      _loadNextPage();
    } else {
      _runSearch(query);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final result = await FriendService.instance.discoverUsers(
        currentUid: _currentUid,
        startAfter: _lastDoc,
      );
      setState(() {
        _users.addAll(result.users);
        _lastDoc = result.lastDoc;
        _hasMore = result.lastDoc != null;
      });
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _loading = true;
    });
    try {
      final results = await FriendService.instance.searchUsers(
        query: query,
        currentUid: _currentUid,
      );
      if (mounted) setState(() => _users = results);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onUserTap(AppUser user) async {
    final status = await FriendService.instance.getRelationshipStatus(
      currentUid: _currentUid,
      otherUid: user.uid,
    );

    if (!mounted) return;

    switch (status) {
      case RelationshipStatus.self:
        context.push('/profile');
      case RelationshipStatus.friend:
        context.push('/friends/${user.uid}/profile');
      case RelationshipStatus.requestSent:
        _showWithdrawSheet(user);
      case RelationshipStatus.requestReceived:
        _showRespondSheet(user);
      case RelationshipStatus.notFriend:
        _showSendRequestSheet(user);
    }
  }

  // ── Bottom Sheets ─────────────────────────────────────────────────────────

  void _showSendRequestSheet(AppUser user) {
    final messageController = TextEditingController(
      text: "Hi, let's connect on Convey!",
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send Friend Request',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'to @${user.username ?? ''}',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.primary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: messageController,
              style: const TextStyle(color: Colors.white),
              maxLines: 3,
              maxLength: 200,
              decoration: InputDecoration(
                hintText: "Hi, let's connect on Convey!",
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF252C3E),
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
                  borderSide: BorderSide(
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                counterStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await FriendService.instance.sendFriendRequest(
                      fromUid: _currentUid,
                      toUid: user.uid,
                      message: messageController.text,
                    );
                    if (mounted) {
                      AppSnackbar.success(context, 'Friend request sent!');
                    }
                  } catch (e) {
                    if (mounted) AppSnackbar.error(context, e.toString());
                  }
                },
                child: const Text(
                  'Send Request',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showWithdrawSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.hourglass_top_rounded,
              color: Colors.white54,
              size: 36,
            ),
            const SizedBox(height: 16),
            Text(
              'Request Pending',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You already sent a friend request to @${user.username ?? ''}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await FriendService.instance.withdrawFriendRequest(
                      fromUid: _currentUid,
                      toUid: user.uid,
                    );
                    if (mounted) {
                      AppSnackbar.success(context, 'Request withdrawn.');
                    }
                  } catch (e) {
                    if (mounted) AppSnackbar.error(context, e.toString());
                  }
                },
                child: const Text('Withdraw Request'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRespondSheet(AppUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2030),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_add_rounded,
              color: Colors.white54,
              size: 36,
            ),
            const SizedBox(height: 16),
            Text(
              'Friend Request Received',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '@${user.username ?? ''} has already sent you a friend request.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _rejectByUid(user.uid);
                    },
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _acceptByUid(user.uid);
                    },
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptByUid(String fromUid) async {
    try {
      // Fetch the request ID first
      final snap = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: fromUid)
          .where('toUid', isEqualTo: _currentUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) throw Exception('Request not found.');
      await FriendService.instance.acceptFriendRequest(
        requestId: snap.docs.first.id,
      );
      if (mounted) AppSnackbar.success(context, 'Friend request accepted!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  Future<void> _rejectByUid(String fromUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromUid', isEqualTo: fromUid)
          .where('toUid', isEqualTo: _currentUid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (snap.docs.isEmpty) throw Exception('Request not found.');
      await FriendService.instance.rejectFriendRequest(
        requestId: snap.docs.first.id,
      );
      if (mounted) AppSnackbar.success(context, 'Request rejected.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        foregroundColor: Colors.white,
        title: const Text('Discover People'),
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by username…',
                hintStyle: const TextStyle(color: Colors.white30),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                        },
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

          // ── User list ──
          Expanded(
            child: _users.isEmpty && _loading
                ? const AppLoadingScreen()
                : _users.isEmpty
                ? const Center(
                    child: Text(
                      'No users found.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _users.length + (_hasMore && !_searching ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _users.length) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      return UserTile(
                        user: _users[index],
                        onTap: () => _onUserTap(_users[index]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

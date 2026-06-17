import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/snackbar.dart';
import '../../onboarding/models/user_model.dart';
import '../models/friend_request_model.dart';
import '../providers/friends_providers.dart';
import '../services/friend_service.dart';
import '../widgets/friend_request_tile.dart';

class FriendRequestsPage extends ConsumerStatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  ConsumerState<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends ConsumerState<FriendRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final String _currentUid = FirebaseAuth.instance.currentUser!.uid;

  // Cache of loaded user profiles keyed by uid to minimise reads
  final Map<String, AppUser?> _userCache = {};

  // Track which request IDs are currently being actioned
  final Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<AppUser?> _getUser(String uid) async {
    if (_userCache.containsKey(uid)) return _userCache[uid];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final user = snap.exists ? AppUser.fromFirestore(snap) : null;
    _userCache[uid] = user;
    return user;
  }

  Future<void> _accept(FriendRequest request) async {
    setState(() => _loadingIds.add(request.id));
    try {
      await FriendService.instance.acceptFriendRequest(requestId: request.id);
      if (mounted) AppSnackbar.success(context, 'Friend request accepted!');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingIds.remove(request.id));
    }
  }

  Future<void> _reject(FriendRequest request) async {
    setState(() => _loadingIds.add(request.id));
    try {
      await FriendService.instance.rejectFriendRequest(requestId: request.id);
      if (mounted) AppSnackbar.success(context, 'Request rejected.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingIds.remove(request.id));
    }
  }

  Future<void> _withdraw(FriendRequest request) async {
    setState(() => _loadingIds.add(request.id));
    try {
      await FriendService.instance.withdrawFriendRequest(
        fromUid: _currentUid,
        toUid: request.toUid,
      );
      if (mounted) AppSnackbar.success(context, 'Request withdrawn.');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _loadingIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final receivedAsync = ref.watch(receivedRequestsProvider);
    final sentAsync = ref.watch(sentRequestsProvider);

    final receivedCount = receivedAsync.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        foregroundColor: Colors.white,
        title: const Text('Friend Requests'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor: Colors.white38,
          indicatorColor: colorScheme.primary,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Received'),
                  if (receivedCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$receivedCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Sent'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Received ──
          receivedAsync.when(
            data: (requests) => requests.isEmpty
                ? const _EmptyState(
                    icon: Icons.inbox_outlined,
                    message: 'No pending requests.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      return FutureBuilder<AppUser?>(
                        future: _getUser(request.fromUid),
                        builder: (context, snap) => ReceivedRequestTile(
                          request: request,
                          fromUser: snap.data,
                          loading: _loadingIds.contains(request.id),
                          onAccept: () => _accept(request),
                          onReject: () => _reject(request),
                        ),
                      );
                    },
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(
              child: Text(e.toString(), style: const TextStyle(color: Colors.redAccent)),
            ),
          ),

          // ── Sent ──
          sentAsync.when(
            data: (requests) => requests.isEmpty
                ? const _EmptyState(
                    icon: Icons.send_outlined,
                    message: 'No pending sent requests.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final request = requests[index];
                      return FutureBuilder<AppUser?>(
                        future: _getUser(request.toUid),
                        builder: (context, snap) => SentRequestTile(
                          request: request,
                          toUser: snap.data,
                          loading: _loadingIds.contains(request.id),
                          onWithdraw: () => _withdraw(request),
                        ),
                      );
                    },
                  ),
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Center(
              child: Text(e.toString(), style: const TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }
}

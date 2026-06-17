// lib/features/chats/pages/chat_page.dart
//
// Changes from original:
//   • initState() calls ActiveChatService.setActiveChat() and updates
//     activeChatProvider (Riverpod) so foreground notification suppression works.
//   • dispose() calls ActiveChatService.clearActiveChat() and clears the provider.
//   • didChangeAppLifecycleState() clears active chat on pause/detach and
//     restores it on resume — handles home-button press during a chat session.
//
// Everything else (UI, scroll, read receipts, typing) is unchanged.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../notifications/active_chat_service.dart';
import '../../notifications/notification_providers.dart';
import '../../profile/widgets/profile_avatar.dart';
import '../models/chat_message_model.dart';
import '../providers/chat_providers.dart';
import '../services/read_receipt_service.dart';
import '../services/typing_service.dart';
import '../utils/presence_lifecycle_mixin.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/message_bubble.dart';

import '../../calls/models/call_model.dart';
import '../../calls/pages/outgoing_call_page.dart';
import '../../calls/providers/call_providers.dart';

class ChatPage extends ConsumerStatefulWidget {
  final String chatId;
  final String displayName;
  final String? photoUrl;
  final String otherUid;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.displayName,
    this.photoUrl,
    required this.otherUid,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver, TypingLifecycleMixin {
  final _scrollController = ScrollController();
  late final ActiveChatService _activeChatService;

  @override
  String get chatId => widget.chatId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    _activeChatService = ref.read(activeChatServiceProvider);

    ref.listenManual(messagesProvider(widget.chatId), (_, next) {
      next.whenData(_markNewestRead);
    });

    // ── Active chat tracking ─────────────────────────────────────────────
    // Set immediately so the foreground notification suppressor (NotificationService)
    // and the Communication Server both know this user is viewing this chat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setActiveChat();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    TypingService.instance.clearTyping(widget.chatId);

    // ── Clear active chat ────────────────────────────────────────────────
    _clearActiveChat();

    super.dispose();
  }

  // ── Lifecycle: handle home-button / app-switch ─────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // User left the app — clear so they receive notifications on other devices.
        _clearActiveChat();
        break;
      case AppLifecycleState.resumed:
        // User came back to this chat — re-set.
        _setActiveChat();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Transition states — do nothing.
        break;
    }
  }

  void _setActiveChat() {
    // Update Riverpod state first (synchronous) for immediate local suppression.
    ref.read(activeChatProvider.notifier).state = widget.chatId;
    // Then update RTDB (async, fire-and-forget for UI responsiveness).
    ActiveChatService.instance.setActiveChat(widget.chatId);
  }

  Future<void> _clearActiveChat() async {
    await _activeChatService.clearActiveChat();
  }

  // ── Scroll ──────────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(messagesProvider(widget.chatId).notifier).loadMore();
    }
  }

  // ── Read receipts ────────────────────────────────────────────────────────

  Future<void> _markNewestRead(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final newestMessage = messages.last;
    if (newestMessage.senderId == currentUid) return;

    final currentReceipt = await ReadReceiptService.instance.getCurrentReceipt(
      widget.chatId,
    );

    if (newestMessage.createdAt <= currentReceipt.lastReadTimestamp) return;

    await ReadReceiptService.instance.markRead(
      chatId: widget.chatId,
      timestamp: newestMessage.createdAt,
    );
  }

  // ── Refresh ────────────────────────────────────────────────────────

  bool _isRefreshing = false;

  Future<void> _refreshChatData() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    ref.invalidate(messagesProvider(widget.chatId));

    ref.invalidate(presenceProvider(widget.otherUid));

    ref.invalidate(typingProvider(typingKey(widget.chatId, widget.otherUid)));

    ref.invalidate(
      readReceiptProvider(readKey(widget.chatId, widget.otherUid)),
    );

    ref.invalidate(chatParticipantProvider(widget.chatId));

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }
  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ;
    final messagesAsync = ref.watch(messagesProvider(widget.chatId));
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final presenceAsync = ref.watch(presenceProvider(widget.otherUid));
    final typingAsync = ref.watch(
      typingProvider(typingKey(widget.chatId, widget.otherUid)),
    );
    final otherReceiptAsync = ref.watch(
      readReceiptProvider(readKey(widget.chatId, widget.otherUid)),
    );

    final presenceLabel = presenceAsync.when(
      data: (p) => p.statusLabel,
      loading: () => '',
      error: (_, _) => '',
    );

    final isOtherTyping = typingAsync.when(
      data: (t) => t.isTyping,
      loading: () => false,
      error: (_, _) => false,
    );

    final otherLastRead = otherReceiptAsync.when(
      data: (r) => r.lastReadTimestamp,
      loading: () => null,
      error: (_, _) => null,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Audio Call',
            icon: const Icon(Icons.call_rounded),
            onPressed: () async {
              await ref
                  .read(callStateProvider.notifier)
                  .startCall(
                    receiverUid: widget.otherUid,
                    receiverName: widget.displayName,
                    receiverPhotoUrl: widget.photoUrl,
                    chatId: widget.chatId,
                    callType: CallType.audio,
                  );

              if (!context.mounted) return;

              context.push('/outgoing-call');
            },
          ),

          IconButton(
            tooltip: 'Video Call',
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () async {
              await ref
                  .read(callStateProvider.notifier)
                  .startCall(
                    receiverUid: widget.otherUid,
                    receiverName: widget.displayName,
                    receiverPhotoUrl: widget.photoUrl,
                    chatId: widget.chatId,
                    callType: CallType.video,
                  );

              if (!context.mounted) return;

              if (context.mounted) {
                context.push('/outgoing-call');
              }
            },
          ),

          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshChatData,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
        backgroundColor: const Color(0xFF0B0F17),
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            ProfileAvatar(
              photoUrl: widget.photoUrl,
              displayName: widget.displayName,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: isOtherTyping
                        ? const Text(
                            'Typing...',
                            key: ValueKey('typing'),
                            style: TextStyle(
                              color: Colors.lightBlueAccent,
                              fontSize: 12,
                            ),
                          )
                        : presenceLabel.isNotEmpty
                        ? Text(
                            presenceLabel,
                            key: ValueKey(presenceLabel),
                            style: TextStyle(
                              color: presenceAsync.value?.online == true
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              fontSize: 12,
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('empty')),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(color: Colors.white10, height: 1),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  '$error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return _EmptyConversation(name: widget.displayName);
                }
                return _MessageList(
                  messages: messages,
                  currentUid: currentUid,
                  scrollController: _scrollController,
                  hasMore: ref
                      .read(messagesProvider(widget.chatId).notifier)
                      .hasMore,
                  otherUserLastReadTimestamp: otherLastRead,
                );
              },
            ),
          ),
          ChatInputBar(
            chatId: widget.chatId,
            recipientUid:
                widget.otherUid, // NEW — passed through to ChatService
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message list (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUid;
  final ScrollController scrollController;
  final bool hasMore;
  final int? otherUserLastReadTimestamp;

  const _MessageList({
    required this.messages,
    required this.currentUid,
    required this.scrollController,
    required this.hasMore,
    this.otherUserLastReadTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: messages.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        final reversedIndex = messages.length - 1 - index;

        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final message = messages[reversedIndex];
        final isMine = message.senderId == currentUid;

        final isLast = reversedIndex == messages.length - 1;
        final nextMessage = reversedIndex < messages.length - 1
            ? messages[reversedIndex + 1]
            : null;
        final showTimestamp =
            isLast ||
            (nextMessage != null &&
                (nextMessage.senderId != message.senderId ||
                    nextMessage.createdAt - message.createdAt > 5 * 60 * 1000));

        return MessageBubble(
          message: message,
          isMine: isMine,
          showTimestamp: showTimestamp,
          otherUserLastReadTimestamp: isMine
              ? otherUserLastReadTimestamp
              : null,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state (unchanged from original)
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyConversation extends StatelessWidget {
  final String name;
  const _EmptyConversation({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Say hi to $name!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This is the start of your conversation.',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

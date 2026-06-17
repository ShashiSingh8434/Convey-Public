// lib/core/widgets/app_lifecycle_handler.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/chats/services/presence_service.dart';
import '../../features/notifications/active_chat_service.dart';
import '../../features/notifications/notification_providers.dart';

class AppLifecycleHandler extends ConsumerStatefulWidget {
  final Widget child;

  const AppLifecycleHandler({super.key, required this.child});

  @override
  ConsumerState<AppLifecycleHandler> createState() =>
      _AppLifecycleHandlerState();
}

class _AppLifecycleHandlerState extends ConsumerState<AppLifecycleHandler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    // Initialize RTDB presence once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PresenceService.instance.initPresence();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Presence
        PresenceService.instance.setOffline();

        // Active chat cleanup
        final activeChatId = ref.read(activeChatProvider);

        if (activeChatId != null) {
          ref.read(activeChatProvider.notifier).state = null;
          ActiveChatService.instance.clearActiveChat();
        }

        break;

      case AppLifecycleState.resumed:
        PresenceService.instance.setOnline();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fcmTokenSyncProvider);

    return widget.child;
  }
}

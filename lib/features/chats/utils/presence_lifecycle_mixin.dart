import 'package:flutter/widgets.dart';

import '../services/presence_service.dart';
import '../services/typing_service.dart';

/// Mixin for the root app widget (or any widget high in the tree) that
/// bridges Flutter's [AppLifecycleState] to [PresenceService].
///
/// Usage — in your root widget State:
///
/// ```dart
/// class _MyAppState extends State<MyApp> with WidgetsBindingObserver, PresenceLifecycleMixin {
///   @override
///   void initState() {
///     super.initState();
///     WidgetsBinding.instance.addObserver(this);
///     PresenceService.instance.initPresence();
///   }
///
///   @override
///   void dispose() {
///     WidgetsBinding.instance.removeObserver(this);
///     super.dispose();
///   }
/// }
/// ```
mixin PresenceLifecycleMixin on WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        PresenceService.instance.setOnline();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        PresenceService.instance.setOffline();
        break;
      case AppLifecycleState.hidden:
        // Android 14+ hidden state — treat as background.
        PresenceService.instance.setOffline();
        break;
    }
  }
}

/// Mixin for the ChatPage State that hooks typing cleanup into lifecycle.
///
/// Usage:
/// ```dart
/// class _ChatPageState extends ConsumerStatefulWidget
///     with WidgetsBindingObserver, TypingLifecycleMixin {
///   late final String chatId = widget.chatId;
/// }
/// ```
mixin TypingLifecycleMixin on WidgetsBindingObserver {
  /// Override this in the mixing class to supply the active chatId.
  String get chatId;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        TypingService.instance.clearTyping(chatId);
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }
}

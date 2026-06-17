// lib/main.dart
//
// Changes from original:
//   1. Register firebaseMessagingBackgroundHandler BEFORE runApp — required
//      by FCM so the isolate handler is registered at the earliest possible point.
//   2. Create a root ProviderContainer before runApp so NotificationService
//      can read providers (activeChatProvider) from outside the widget tree.
//   3. Pass the container to ProviderScope via `parent` — this is the official
//      Riverpod pattern for sharing a container with non-widget code.
//   4. Call NotificationService.initialize() after Firebase.initializeApp().

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/widgets/app_lifecycle_handler.dart';
import 'firebase_options.dart';

// At the top of main.dart, outside main()
late final ProviderContainer globalContainer;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseDatabase.instance.databaseURL =
      '*** update this with the RTDB url ***';

  globalContainer = ProviderContainer();

  await NotificationService.instance.initialize(globalContainer);

  // ProviderScope creates its own internal container.
  // We pass overrides: [] just to keep it clean.
  runApp(
    UncontrolledProviderScope(
      container: globalContainer,
      child: const ConveyApp(),
    ),
  );
}

class ConveyApp extends StatelessWidget {
  const ConveyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLifecycleHandler(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Convey',
        routerConfig: AppRouter.router,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      ),
    );
  }
}

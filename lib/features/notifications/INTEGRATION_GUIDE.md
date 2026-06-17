# Convey — Push Notification Integration Guide

## 1. Architecture Review

### Existing Architecture (Preserved)
- **Auth**: Firebase Auth → `authStateProvider` → `userDocumentProvider`
- **Routing**: GoRouter + `GoRouterRefreshStream` (auth-driven redirects)
- **Chat**: Firestore metadata (`chats/{chatId}`) + RTDB messages (`messages/{chatId}/{messageId}`)
- **Presence**: RTDB `status/{uid}`
- **Typing**: RTDB `typing/{chatId}/{uid}`
- **Read Receipts**: RTDB `reads/{chatId}/{uid}`
- **State**: Riverpod (StreamProvider, AsyncNotifier, StateProvider.family)

### Notification Layer (New)
```
Message Send Flow:
  sendTextMessage() → sendImageMessage() → sendAudioMessage()
       ↓
  NotificationService.sendChatNotification()
       ↓
  POST /api/notifications/chat   (Communication Server)

Token Lifecycle:
  App Launch / Auth → FCM Token → Firestore users/{uid}.fcmTokens[]
  Token Refresh     → update Firestore
  Logout            → remove token from Firestore

Active Chat Tracking:
  ChatPage.initState  → RTDB activeChats/{uid} = { chatId, updatedAt }
  ChatPage.dispose    → RTDB activeChats/{uid} = null
  App background      → RTDB activeChats/{uid} = null   (AppLifecycleHandler)

Notification Receipt:
  Foreground  → flutter_local_notifications (custom UI)
  Background  → OS handles, tap → deep link to /chat/{chatId}
  Terminated  → OS handles, tap → deep link to /chat/{chatId}
```

### Future WebRTC Call Notifications
The `NotificationService` is designed with a `NotificationType` enum and separate
`sendCallNotification()`, `respondToCall()` methods so call notifications slot in
without touching chat code.

---

## 2. Required pubspec.yaml Changes

Add to `dependencies:`:

```yaml
firebase_messaging: ^15.0.0
flutter_local_notifications: ^18.0.0
```

No other dependencies needed — `http` is already present.

---

## 3. File Map

### New Files
| File | Purpose |
|------|---------|
| `lib/core/notifications/notification_service.dart` | FCM init, token management, foreground display, deep-link routing |
| `lib/core/notifications/notification_api_client.dart` | HTTP client for Communication Server |
| `lib/core/notifications/active_chat_service.dart` | RTDB `activeChats/{uid}` read/write |
| `lib/core/notifications/notification_providers.dart` | Riverpod providers for notification layer |

### Modified Files
| File | Why |
|------|-----|
| `pubspec.yaml` | Add FCM + local notifications deps |
| `lib/main.dart` | Initialize FCM, wire background handler |
| `lib/core/router/app_router.dart` | Handle notification deep-link extras |
| `lib/core/widgets/app_lifecycle_handler.dart` | Clear active chat on background |
| `lib/features/auth/services/auth_service.dart` | Remove FCM token on logout |
| `lib/features/chats/services/chat_service.dart` | Call notification API after send |
| `lib/features/chats/pages/chat_page.dart` | Set/clear active chat |

### Android
| File | Why |
|------|-----|
| `android/app/src/main/AndroidManifest.xml` | FCM service, notification channel, deep-link intent filter |
| `android/app/src/main/res/drawable/ic_notification.xml` | Monochrome notification icon |

---

## 4. Complete File Contents

See the individual `.dart` files delivered alongside this guide.
Each file is self-contained and drop-in ready.

---

## 5. AndroidManifest.xml Changes

See `android_manifest_additions.xml` for the exact XML blocks to merge.

---

## 6–18. Implementation Notes

### Token Registration & Refresh (§8, §9)
`NotificationService.initialize()` is called once in `main()`.
It requests permission, gets the current token, saves it, and registers
`onTokenRefresh` to keep Firestore in sync automatically.
Device ID is derived from `android_id` / `identifierForVendor` — we use a
stable hash of the FCM token's first 16 chars to avoid adding another package.

### Logout Cleanup (§10)
`AuthService.signOut()` now calls `NotificationService.removeCurrentToken()`
before `_auth.signOut()`. This deletes only the token for this device from
Firestore (array element removal via `FieldValue.arrayRemove`).

### Foreground Notifications (§11)
`FirebaseMessaging.onMessage` listener in `NotificationService.initialize()`.
When a `chat` notification arrives while the app is open:
- If the user is already on that chat → suppress (no duplicate noise).
- Otherwise → show a local notification via `flutter_local_notifications`.

### Background / Terminated Notifications (§12, §13)
FCM handles display automatically via the `notification` payload.
The `onBackgroundMessage` top-level handler (`_firebaseMessagingBackgroundHandler`)
is registered before `runApp` for data-only messages (future call signals).
Tapping a notification triggers `onMessageOpenedApp` (background) or
`getInitialMessage()` (terminated), both handled in `NotificationService`.

### Deep Linking (§14)
`NotificationService._handleMessage()` extracts `chatId`, `displayName`,
`photoUrl`, `otherUid` from the FCM data payload and calls
`AppRouter.router.go('/chat/$chatId', extra: {...})`.
No router changes are required — the existing `/chat/:chatId` route already
accepts an `extra` map.

### Active Chat Tracking (§15)
`ActiveChatService` has three methods:
- `setActiveChat(chatId)` — called in `ChatPage.initState`
- `clearActiveChat()` — called in `ChatPage.dispose`
- `getActiveChatId(uid)` — used by Communication Server (server-side read)

`AppLifecycleHandler` already exists. We add a `clearActiveChat()` call inside
its `didChangeAppLifecycleState` when state is `paused` or `detached`.

### Riverpod Integration (§16)
`notificationServiceProvider` is a plain `Provider<NotificationService>` so it
can be read anywhere. `activeChatProvider` is a `StateProvider<String?>` that
`ChatPage` updates; `AppLifecycleHandler` watches it to clear RTDB on pause.

### Communication Server Integration (§17)
`NotificationApiClient` is a thin HTTP wrapper. `ChatService.sendTextMessage()`
(and the image/audio variants) call `NotificationService.sendChatNotification()`
after the Firestore metadata update. The notification is fire-and-forget wrapped
in try/catch so a server error never breaks message delivery.

### WebRTC Readiness (§18)
`NotificationApiClient` already has stub methods:
`sendCallInvite`, `acceptCall`, `rejectCall`, `endCall`.
`NotificationService._handleMessage()` has a `switch` on `type` that routes
`incoming_call`, `call_accepted`, etc. to a no-op handler today —
replace with real WebRTC logic when ready.

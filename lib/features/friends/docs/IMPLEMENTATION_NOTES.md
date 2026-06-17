# Convey – Friend System: Implementation Reference

---

## 1. Complete File Structure

```
lib/
├── core/
│   ├── providers/
│   │   └── providers.dart                  [EXISTING — unchanged]
│   └── router/
│       └── app_router.dart                 [MODIFIED]
│
├── features/
│   ├── dashboard/
│   │   └── dashboard_page.dart             [MODIFIED]
│   │
│   ├── friends/                            [NEW]
│   │   ├── models/
│   │   │   ├── friend_request_model.dart
│   │   │   ├── friendship_model.dart
│   │   │   └── relationship_status.dart
│   │   ├── services/
│   │   │   └── friend_service.dart
│   │   ├── providers/
│   │   │   └── friends_providers.dart
│   │   ├── pages/
│   │   │   ├── discover_users_page.dart
│   │   │   ├── friend_requests_page.dart
│   │   │   ├── friends_page.dart
│   │   │   └── friend_profile_page.dart
│   │   └── widgets/
│   │       ├── user_tile.dart
│   │       ├── friend_tile.dart
│   │       └── friend_request_tile.dart
│   │
│   └── profile/                            [EXISTING — unchanged]
│       ├── pages/profile_page.dart
│       └── widgets/...
│
├── shared/
│   └── widgets/
│       ├── loading_screen.dart             [EXISTING — unchanged]
│       └── snackbar.dart                   [EXISTING — unchanged]

firestore.indexes.json                      [NEW]
firestore.rules                             [NEW]
```

---

## 2. New Routes (app_router.dart additions)

| Path                        | Widget                | Notes                                         |
|-----------------------------|-----------------------|-----------------------------------------------|
| `/discover`                 | `DiscoverUsersPage`   | Paginated browse + search                     |
| `/friend-requests`          | `FriendRequestsPage`  | Tabbed: Received / Sent                       |
| `/friends`                  | `FriendsPage`         | Friend list with local filter + swipe-remove  |
| `/friends/:uid/profile`     | `FriendProfilePage`   | Read-only, guarded by friendship check        |

---

## 3. New Providers (friends_providers.dart)

| Provider                     | Type                                | Description                                         |
|------------------------------|-------------------------------------|-----------------------------------------------------|
| `currentUidProvider`         | `Provider<String?>`                 | Shortcut to current Firebase UID                    |
| `receivedRequestsProvider`   | `StreamProvider<List<FriendRequest>>`| Live stream of pending received requests           |
| `sentRequestsProvider`       | `StreamProvider<List<FriendRequest>>`| Live stream of pending sent requests              |
| `friendshipsProvider`        | `StreamProvider<List<Friendship>>`  | Live stream of all user friendships                 |
| `friendUsersProvider`        | `StreamProvider<List<AppUser>>`     | Resolved user docs for each friendship              |
| `relationshipStatusProvider` | `FutureProvider.family<RelationshipStatus, String>` | Status between current user and `otherUid` |
| `pendingRequestCountProvider`| `Provider<int>`                     | Badge count for drawer                              |

---

## 4. Required Firestore Composite Indexes

Deploy with: `firebase deploy --only firestore:indexes`

### friend_requests
| Fields                              | Direction           | Purpose                            |
|-------------------------------------|---------------------|------------------------------------|
| `toUid` ASC, `status` ASC, `createdAt` DESC   | COLLECTION | Received requests tab    |
| `fromUid` ASC, `status` ASC, `createdAt` DESC | COLLECTION | Sent requests tab        |
| `fromUid` ASC, `toUid` ASC, `status` ASC      | COLLECTION | Relationship status checks |

### friendships
| Fields       | Direction  | Purpose              |
|--------------|------------|----------------------|
| `user1` ASC  | COLLECTION | Friends query (user1)|
| `user2` ASC  | COLLECTION | Friends query (user2)|

### users
| Fields                                    | Direction  | Purpose              |
|-------------------------------------------|------------|----------------------|
| `profileCompleted` ASC, `usernameLower` ASC | COLLECTION | Discover page        |

---

## 5. pubspec.yaml — No New Packages Required

All features use packages already present in a standard Convey setup:
- `cloud_firestore` — all Firestore operations
- `firebase_auth` — current user UID
- `flutter_riverpod` — state management (providers)
- `go_router` — navigation
- `image_picker` — already used in ProfilePage (no new usage needed here)

The `Badge` widget used in the drawer requires Flutter ≥ 3.7 (Material 3).
If targeting Flutter < 3.7, replace:
```dart
Badge(label: Text('$badge'), child: Icon(icon))
```
with a custom Stack/Positioned overlay.

---

## 6. Implementation Decisions

### Deterministic Friendship IDs
`getFriendshipId` sorts UIDs lexicographically and joins with `_`.
This means `areFriends(A, B)` is a single Firestore document read —
no query needed. This is the single most important read-optimization
in the whole system.

### Friendship + getFriends() uses two queries merged in asyncMap
Firestore (without OR queries) requires two reads to get all friendships
for a user. The `getFriends()` stream does a `snapshots()` on `user1`
and an `async .get()` on `user2` inside `asyncMap`. This is a known
Firestore limitation. The tradeoff is one extra read per stream event;
for reasonable friend counts (< 1000) this is acceptable. When Firestore
SDK adds stable OR query support in your target SDK version you can
replace with a single `where Filter.or(...)` call.

### No automatic chat creation
`acceptFriendRequest` only creates a `friendships` document.
No `chats` document is created. Chat creation is intentionally deferred
to first-message-send logic, which can simply call
`FriendService.instance.areFriends(uidA, uidB)` before writing.

### Withdrawal = delete, not status update
Withdrawn requests are hard-deleted. This avoids polluting the
`friend_requests` collection with stale state and eliminates the need
for a `withdrawn` index. The spec explicitly requires this.

### Rejected requests are kept
`rejectFriendRequest` sets `status = rejected` and `respondedAt = now`.
This preserves a history for future moderation use (e.g. rate-limiting
repeated requests). Rejected requests are never shown in the UI.

### Pagination strategy
- **Discover page**: cursor-based (`startAfterDocument`) with page size 15.
  Scroll-to-bottom triggers `_loadNextPage()`.
- **Search**: prefix-range query (`>=` / `< \uf8ff`). Search always replaces
  the list; no pagination in search mode (limited to 20 results).
- **Friend requests / Friends**: Riverpod stream providers — no manual
  pagination needed as these lists are bounded by real social graphs.

### User cache in FriendRequestsPage
`_userCache` is a `Map<String, AppUser?>` held in the widget state.
FutureBuilder calls `_getUser(uid)` which checks the map before hitting
Firestore. This halves reads when a stream re-emits (e.g. after accept/reject)
since the sender's profile is already known.

### Discover page relationship check on tap
`_onUserTap` performs a fresh `getRelationshipStatus` call on every tap.
This is intentional — it avoids stale state from a cached status if the
relationship changed while the user was browsing. The call is ~2-3 Firestore
reads and is acceptable latency for a tap handler.

### FriendProfilePage access gate
`_loadProfile()` calls `areFriends()` *before* loading any user data.
If the friendship no longer exists (e.g. removed in another session),
the page shows a "friends only" lock screen rather than an error.
The friendship document read costs 1 Firestore read.

### Badge widget for drawer
`pendingRequestCountProvider` is a derived `Provider<int>` that reads
`receivedRequestsProvider`. The count auto-updates whenever the stream
emits. The `Badge` Material 3 widget renders inline in `_DrawerItem`.

---

## 7. Edge Cases Handled

| Edge Case | Handling |
|-----------|----------|
| A → B pending, B → A also tries to send | `getRelationshipStatus` checks both directions; `sendFriendRequest` throws `FriendException` |
| Race condition: two users claim same username simultaneously | Existing `UserService.claimUsername` transaction handles this (unchanged) |
| Two users tap "Accept" for the same request simultaneously | Firestore transaction in `acceptFriendRequest` reads the request inside the tx; second caller sees `status != pending` and throws |
| Friendship exists, user navigates to `/friends/:uid/profile` while friend removes them | `_loadProfile` re-checks `areFriends` on mount; shows lock screen |
| Current user appears in discover results | Excluded via `where((u) => u.uid != currentUid)` filter after query |
| Search query with special Firestore characters | `usernameLower` is already sanitized at write-time; prefix query is safe |
| Empty message in send request sheet | Defaults to `"Hi, let's connect on Convey!"` |
| User deletes account mid-friendship | `FriendTile` / `FriendProfilePage` gracefully handles null `AppUser` from Firestore (snap.exists check) |
| Drawer badge overflows (e.g. 99+ requests) | `Badge` widget handles overflow natively in Flutter 3.7+; if needed, add `.clamp(0, 99)` |

---

## 8. Future Chat Compatibility

To create a chat when the first message is sent:

```dart
// In a future ChatService.sendFirstMessage():
final areFriends = await FriendService.instance.areFriends(
  senderUid,
  recipientUid,
);
if (!areFriends) throw Exception('Must be friends to start a chat.');

// Then create the chat document and the first message atomically.
```

The `friendships/{friendshipId}` document ID is stable and deterministic,
so it can serve as the canonical way to check permission before messaging,
calling, etc. without any schema changes.

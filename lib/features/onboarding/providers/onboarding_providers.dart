import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/user_service.dart';

/// Debounced username availability check.
/// Pass the already-lowercased username.
final usernameAvailabilityProvider = FutureProvider.family<bool, String>((
  ref,
  usernameLower,
) async {
  if (usernameLower.isEmpty) return false;
  return UserService.instance.isUsernameAvailable(usernameLower);
});

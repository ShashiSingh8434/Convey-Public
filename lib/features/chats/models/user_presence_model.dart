class UserPresence {
  final String uid;
  final bool online;
  final DateTime? lastSeen;

  /// Call state
  final bool isInCall;
  final String? currentCallId;
  final String? callType; // audio | video

  const UserPresence({
    required this.uid,
    required this.online,
    this.lastSeen,
    this.isInCall = false,
    this.currentCallId,
    this.callType,
  });

  factory UserPresence.fromRtdb(String uid, Map<dynamic, dynamic> data) {
    final lastSeenRaw = data['lastSeen'];

    DateTime? lastSeen;
    if (lastSeenRaw is int && lastSeenRaw > 0) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenRaw);
    }

    return UserPresence(
      uid: uid,
      online: data['online'] as bool? ?? false,
      lastSeen: lastSeen,

      isInCall: data['isInCall'] as bool? ?? false,

      currentCallId: data['currentCallId'] as String?,

      callType: data['callType'] as String?,
    );
  }

  factory UserPresence.offline(String uid) =>
      UserPresence(uid: uid, online: false, lastSeen: null);

  UserPresence copyWith({
    bool? online,
    DateTime? lastSeen,
    bool? isInCall,
    String? currentCallId,
    String? callType,
  }) {
    return UserPresence(
      uid: uid,
      online: online ?? this.online,
      lastSeen: lastSeen ?? this.lastSeen,
      isInCall: isInCall ?? this.isInCall,
      currentCallId: currentCallId ?? this.currentCallId,
      callType: callType ?? this.callType,
    );
  }

  /// Human-readable status label shown in chat app bar.
  String get statusLabel {
    if (isInCall) {
      return callType == 'video' ? 'In a video call' : 'In a call';
    }

    if (online) return 'Online';

    final ls = lastSeen;
    if (ls == null) return 'Offline';

    final diff = DateTime.now().difference(ls);

    if (diff.inMinutes < 1) return 'Last seen just now';
    if (diff.inMinutes < 60) {
      return 'Last seen ${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24) {
      return 'Last seen ${diff.inHours}h ago';
    }
    if (diff.inDays == 1) {
      return 'Last seen yesterday';
    }

    return 'Last seen ${diff.inDays}d ago';
  }

  bool get canReceiveCalls => !isInCall;
}

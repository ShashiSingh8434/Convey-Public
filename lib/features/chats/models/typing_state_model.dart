class TypingState {
  final String chatId;
  final String uid;
  final bool isTyping;
  final DateTime updatedAt;

  const TypingState({
    required this.chatId,
    required this.uid,
    required this.isTyping,
    required this.updatedAt,
  });

  factory TypingState.fromRtdb(
    String chatId,
    String uid,
    Map<dynamic, dynamic> data,
  ) {
    final updatedAtRaw = data['updatedAt'];
    final updatedAt = (updatedAtRaw is int && updatedAtRaw > 0)
        ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw)
        : DateTime.now();

    return TypingState(
      chatId: chatId,
      uid: uid,
      isTyping: data['typing'] as bool? ?? false,
      updatedAt: updatedAt,
    );
  }

  factory TypingState.idle(String chatId, String uid) => TypingState(
    chatId: chatId,
    uid: uid,
    isTyping: false,
    updatedAt: DateTime.now(),
  );
}

class ReadReceipt {
  final String chatId;
  final String uid;
  final int lastReadTimestamp; // Unix milliseconds

  const ReadReceipt({
    required this.chatId,
    required this.uid,
    required this.lastReadTimestamp,
  });

  factory ReadReceipt.fromRtdb(
    String chatId,
    String uid,
    Map<dynamic, dynamic> data,
  ) {
    return ReadReceipt(
      chatId: chatId,
      uid: uid,
      lastReadTimestamp: data['lastReadTimestamp'] as int? ?? 0,
    );
  }

  factory ReadReceipt.empty(String chatId, String uid) =>
      ReadReceipt(chatId: chatId, uid: uid, lastReadTimestamp: 0);

  DateTime get lastReadAt =>
      DateTime.fromMillisecondsSinceEpoch(lastReadTimestamp);

  /// Returns true if the given message timestamp has been read by this user.
  bool hasRead(int messageCreatedAt) => lastReadTimestamp >= messageCreatedAt;
}

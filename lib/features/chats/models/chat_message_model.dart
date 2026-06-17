class ChatMessage {
  final String id;
  final String senderId;
  final String type;
  final String content;
  final int createdAt; // Unix milliseconds — RTDB stores as int

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromRtdb(String id, Map<dynamic, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId: data['senderId'] as String? ?? '',
      type: data['type'] as String? ?? 'text',
      content: data['content'] as String? ?? '',
      createdAt: data['createdAt'] as int? ?? 0,
    );
  }

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(createdAt);

  Map<String, dynamic> toRtdb() => {
    'senderId': senderId,
    'type': type,
    'content': content,
    'createdAt': createdAt,
  };
}

import 'package:cloud_firestore/cloud_firestore.dart';

class Chat {
  final String id;
  final List<String> participants;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;
  final String? lastMessageType;
  final String? lastMessageSender;

  const Chat({
    required this.id,
    required this.participants,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageSender,
  });

  factory Chat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Chat(
      id: doc.id,
      participants: List<String>.from(data['participants'] as List? ?? []),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMessage: data['lastMessage'] as String?,
      lastMessageType: data['lastMessageType'] as String?,
      lastMessageSender: data['lastMessageSender'] as String?,
    );
  }

  /// Returns the other participant's UID given the current user's UID.
  String otherUid(String currentUid) =>
      participants.firstWhere((uid) => uid != currentUid, orElse: () => '');

  Map<String, dynamic> toMap() => {
    'participants': participants,
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'lastMessage': lastMessage,
    'lastMessageType': lastMessageType,
    'lastMessageSender': lastMessageSender,
  };
}

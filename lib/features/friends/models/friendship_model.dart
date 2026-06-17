import 'package:cloud_firestore/cloud_firestore.dart';

class Friendship {
  final String id;
  final String user1;
  final String user2;
  final DateTime createdAt;

  const Friendship({
    required this.id,
    required this.user1,
    required this.user2,
    required this.createdAt,
  });

  factory Friendship.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Friendship(
      id: doc.id,
      user1: data['user1'] as String? ?? '',
      user2: data['user2'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'user1': user1,
    'user2': user2,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  /// Returns the UID of the other user in the friendship.
  String otherUid(String currentUid) => user1 == currentUid ? user2 : user1;
}

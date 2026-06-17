import 'package:cloud_firestore/cloud_firestore.dart';

enum FriendRequestStatus { pending, accepted, rejected }

extension FriendRequestStatusX on FriendRequestStatus {
  String get value {
    switch (this) {
      case FriendRequestStatus.pending:
        return 'pending';
      case FriendRequestStatus.accepted:
        return 'accepted';
      case FriendRequestStatus.rejected:
        return 'rejected';
    }
  }

  static FriendRequestStatus fromString(String s) {
    switch (s) {
      case 'accepted':
        return FriendRequestStatus.accepted;
      case 'rejected':
        return FriendRequestStatus.rejected;
      default:
        return FriendRequestStatus.pending;
    }
  }
}

class FriendRequest {
  final String id;
  final String fromUid;
  final String toUid;
  final String message;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const FriendRequest({
    required this.id,
    required this.fromUid,
    required this.toUid,
    required this.message,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  factory FriendRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendRequest(
      id: doc.id,
      fromUid: data['fromUid'] as String? ?? '',
      toUid: data['toUid'] as String? ?? '',
      message: data['message'] as String? ?? '',
      status: FriendRequestStatusX.fromString(
        data['status'] as String? ?? 'pending',
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'fromUid': fromUid,
    'toUid': toUid,
    'message': message,
    'status': status.value,
    'createdAt': Timestamp.fromDate(createdAt),
    'respondedAt':
        respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
  };

  FriendRequest copyWith({
    FriendRequestStatus? status,
    DateTime? respondedAt,
  }) => FriendRequest(
    id: id,
    fromUid: fromUid,
    toUid: toUid,
    message: message,
    status: status ?? this.status,
    createdAt: createdAt,
    respondedAt: respondedAt ?? this.respondedAt,
  );
}

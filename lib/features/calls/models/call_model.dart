// lib/features/calls/models/call_model.dart
//
// Mirrors the RTDB calls/{callId} document and the Firestore call_history
// collection. Two factories cover both sources.

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallType
// ─────────────────────────────────────────────────────────────────────────────

enum CallType {
  audio,
  video;

  static CallType fromString(String? value) =>
      value == 'video' ? CallType.video : CallType.audio;

  String get value => name; // 'audio' | 'video'
}

// ─────────────────────────────────────────────────────────────────────────────
// CallStatus — RTDB status field
// ─────────────────────────────────────────────────────────────────────────────

enum CallStatus {
  ringing,
  accepted,
  connected,
  rejected,
  busy,
  ended,
  timeout;

  static CallStatus fromString(String? value) => switch (value) {
    'ringing' => ringing,
    'accepted' => accepted,
    'connected' => connected,
    'rejected' => rejected,
    'busy' => busy,
    'ended' => ended,
    'timeout' => timeout,
    _ => ended,
  };

  String get value => name;
}

// ─────────────────────────────────────────────────────────────────────────────
// CallHistoryStatus — Firestore call_history status field
// ─────────────────────────────────────────────────────────────────────────────

enum CallHistoryStatus {
  completed,
  missed,
  rejected,
  cancelled,
  failed;

  String get value => name;
}

// ─────────────────────────────────────────────────────────────────────────────
// SdpDescription — wraps offer / answer
// ─────────────────────────────────────────────────────────────────────────────

class SdpDescription {
  final String type; // 'offer' | 'answer'
  final String sdp;

  const SdpDescription({required this.type, required this.sdp});

  factory SdpDescription.fromMap(Map<dynamic, dynamic> map) => SdpDescription(
    type: map['type'] as String? ?? '',
    sdp: map['sdp'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {'type': type, 'sdp': sdp};
}

// ─────────────────────────────────────────────────────────────────────────────
// CallModel — RTDB calls/{callId} document
// ─────────────────────────────────────────────────────────────────────────────

class CallModel {
  final String callId;
  final String callerId;
  final String receiverId;
  final CallType type;
  final CallStatus status;
  final int createdAt;
  final SdpDescription? offer;
  final SdpDescription? answer;

  const CallModel({
    required this.callId,
    required this.callerId,
    required this.receiverId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.offer,
    this.answer,
  });

  factory CallModel.fromRtdb(String id, Map<dynamic, dynamic> data) {
    SdpDescription? offer;
    if (data['offer'] != null) {
      offer = SdpDescription.fromMap(
        Map<dynamic, dynamic>.from(data['offer'] as Map),
      );
    }

    SdpDescription? answer;
    if (data['answer'] != null) {
      answer = SdpDescription.fromMap(
        Map<dynamic, dynamic>.from(data['answer'] as Map),
      );
    }

    return CallModel(
      callId: id,
      callerId: data['callerId'] as String? ?? '',
      receiverId: data['receiverId'] as String? ?? '',
      type: CallType.fromString(data['type'] as String?),
      status: CallStatus.fromString(data['status'] as String?),
      createdAt: data['createdAt'] as int? ?? 0,
      offer: offer,
      answer: answer,
    );
  }

  Map<String, dynamic> toRtdbMap() => {
    'callerId': callerId,
    'receiverId': receiverId,
    'type': type.value,
    'status': status.value,
    'createdAt': createdAt,
    'offer': offer?.toMap(),
    'answer': null,
  };

  CallModel copyWith({CallStatus? status, SdpDescription? answer}) => CallModel(
    callId: callId,
    callerId: callerId,
    receiverId: receiverId,
    type: type,
    status: status ?? this.status,
    createdAt: createdAt,
    offer: offer,
    answer: answer ?? this.answer,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CallHistory — Firestore call_history/{callId} document
// ─────────────────────────────────────────────────────────────────────────────

class CallHistory {
  final String callId;
  final String callerId;
  final String callerName;
  final String? callerPhotoUrl;
  final String receiverId;
  final String receiverName;
  final String? receiverPhotoUrl;
  final CallType type;
  final CallHistoryStatus status;
  final int? durationSeconds;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime createdAt;

  const CallHistory({
    required this.callId,
    required this.callerId,
    required this.callerName,
    this.callerPhotoUrl,
    required this.receiverId,
    required this.receiverName,
    this.receiverPhotoUrl,
    required this.type,
    required this.status,
    this.durationSeconds,
    this.startedAt,
    this.endedAt,
    required this.createdAt,
  });

  factory CallHistory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CallHistory(
      callId: data['callId'] as String? ?? doc.id,
      callerId: data['callerId'] as String? ?? '',
      callerName: data['callerName'] as String? ?? '',
      callerPhotoUrl: data['callerPhotoUrl'] as String?,
      receiverId: data['receiverId'] as String? ?? '',
      receiverName: data['receiverName'] as String? ?? '',
      receiverPhotoUrl: data['receiverPhotoUrl'] as String?,
      type: CallType.fromString(data['type'] as String?),
      status: _statusFromString(data['status'] as String?),
      durationSeconds: data['durationSeconds'] as int?,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  static CallHistoryStatus _statusFromString(String? value) => switch (value) {
    'completed' => CallHistoryStatus.completed,
    'missed' => CallHistoryStatus.missed,
    'rejected' => CallHistoryStatus.rejected,
    'cancelled' => CallHistoryStatus.cancelled,
    _ => CallHistoryStatus.failed,
  };

  Map<String, dynamic> toFirestoreMap() => {
    'callId': callId,
    'callerId': callerId,
    'callerName': callerName,
    'callerPhotoUrl': callerPhotoUrl,
    'receiverId': receiverId,
    'receiverName': receiverName,
    'receiverPhotoUrl': receiverPhotoUrl,
    'type': type.value,
    'status': status.value,
    'durationSeconds': durationSeconds,
    'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
    'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

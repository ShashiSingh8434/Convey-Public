// lib/features/calls/models/ice_candidate_model.dart
//
// Wraps flutter_webrtc RTCIceCandidate for RTDB serialisation.
// Path: callCandidates/{callId}/caller|receiver/{pushKey}

import 'package:flutter_webrtc/flutter_webrtc.dart';

class IceCandidateModel {
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  const IceCandidateModel({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  factory IceCandidateModel.fromRtdb(Map<dynamic, dynamic> data) =>
      IceCandidateModel(
        candidate: data['candidate'] as String? ?? '',
        sdpMid: data['sdpMid'] as String? ?? '',
        sdpMLineIndex: data['sdpMLineIndex'] as int? ?? 0,
      );

  factory IceCandidateModel.fromRtcCandidate(RTCIceCandidate c) =>
      IceCandidateModel(
        candidate: c.candidate ?? '',
        sdpMid: c.sdpMid ?? '',
        sdpMLineIndex: c.sdpMLineIndex ?? 0,
      );

  Map<String, dynamic> toMap() => {
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };

  RTCIceCandidate toRtcCandidate() =>
      RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
}

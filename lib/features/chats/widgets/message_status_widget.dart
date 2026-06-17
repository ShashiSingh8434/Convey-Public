import 'package:flutter/material.dart';

// ── Status enum ───────────────────────────────────────────────────────────────

/// Delivery status shown on outgoing message bubbles.
enum MessageStatus { sent, seen }

// ── Public widget ─────────────────────────────────────────────────────────────

/// Renders the delivery status icon for an outgoing message.
///
/// Shows double-check marks in grey (sent) or blue (seen).
/// Returns [SizedBox.shrink] when [status] is null (incoming messages).
class MessageStatusWidget extends StatelessWidget {
  final MessageStatus? status;

  const MessageStatusWidget({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();

    switch (status!) {
      case MessageStatus.seen:
        return const _DoubleCheckIcon(seen: true);
      case MessageStatus.sent:
        return const _DoubleCheckIcon(seen: false);
    }
  }
}

// ── Internal icons ────────────────────────────────────────────────────────────

/// Two overlapping check marks — blue when seen, grey when only sent.
class _DoubleCheckIcon extends StatelessWidget {
  final bool seen;
  const _DoubleCheckIcon({required this.seen});

  @override
  Widget build(BuildContext context) {
    final color = seen ? Colors.lightBlueAccent : Colors.white38;
    return SizedBox(
      width: 18,
      height: 12,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Icon(Icons.check_rounded, size: 12, color: color),
          ),
          Positioned(
            left: 5,
            child: Icon(Icons.check_rounded, size: 12, color: color),
          ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Computes [MessageStatus] from read-receipt data.
///
/// Returns `null` for incoming messages (never show status on theirs).
/// Returns [MessageStatus.sent] if no read-receipt data is available yet.
/// Returns [MessageStatus.seen] if [otherUserLastReadTimestamp] ≥ [messageCreatedAt].
MessageStatus? computeStatus({
  required bool isMine,
  required int messageCreatedAt,
  required int? otherUserLastReadTimestamp,
}) {
  if (!isMine) return null;
  if (otherUserLastReadTimestamp == null) return MessageStatus.sent;
  return otherUserLastReadTimestamp >= messageCreatedAt
      ? MessageStatus.seen
      : MessageStatus.sent;
}

import 'package:flutter/material.dart';

import '../models/chat_message_model.dart';
import 'message_status_widget.dart';

class TextMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTimestamp;
  final int? otherUserLastReadTimestamp;

  const TextMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTimestamp = false,
    this.otherUserLastReadTimestamp,
  });

  MessageStatus? get _status => computeStatus(
    isMine: isMine,
    messageCreatedAt: message.createdAt,
    otherUserLastReadTimestamp: otherUserLastReadTimestamp,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _status;

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine ? colorScheme.primary : const Color(0xFF1E2535),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.3,
            ),
          ),
        ),
        if (showTimestamp || status != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showTimestamp)
                  Text(
                    _formatTime(
                      DateTime.fromMillisecondsSinceEpoch(message.createdAt),
                    ),
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                if (showTimestamp && status != null) const SizedBox(width: 4),
                MessageStatusWidget(status: status),
              ],
            ),
          ),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

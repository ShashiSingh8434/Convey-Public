import 'package:flutter/material.dart';

import '../models/chat_message_model.dart';
import 'audio_message_bubble.dart';
import 'image_message_bubble.dart';
import 'text_message_bubble.dart';

/// Routes each [ChatMessage] to the appropriate typed bubble widget.
///
/// This widget is a dispatcher only — it contains no UI logic of its own.
/// All rendering is delegated to [TextMessageBubble], [ImageMessageBubble],
/// or [AudioMessageBubble].
///
/// Adding support for a new type (video, file, reaction) means adding a
/// single case here and creating the corresponding bubble widget.
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTimestamp;

  /// The other participant's last-read timestamp, used for seen status.
  /// Only relevant for outgoing messages. Pass null to show no status icon.
  final int? otherUserLastReadTimestamp;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTimestamp = false,
    this.otherUserLastReadTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isMine ? 64 : 12,
        right: isMine ? 12 : 64,
        top: 2,
        bottom: 2,
      ),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [_buildBubble()],
      ),
    );
  }

  Widget _buildBubble() {
    switch (message.type) {
      case 'image':
        return ImageMessageBubble(
          message: message,
          isMine: isMine,
          showTimestamp: showTimestamp,
          otherUserLastReadTimestamp: otherUserLastReadTimestamp,
        );

      case 'audio':
        return AudioMessageBubble(
          message: message,
          isMine: isMine,
          showTimestamp: showTimestamp,
          otherUserLastReadTimestamp: otherUserLastReadTimestamp,
        );

      case 'text':
      default:
        // Unknown future types fall back to text so nothing crashes.
        return TextMessageBubble(
          message: message,
          isMine: isMine,
          showTimestamp: showTimestamp,
          otherUserLastReadTimestamp: otherUserLastReadTimestamp,
        );
    }
  }
}

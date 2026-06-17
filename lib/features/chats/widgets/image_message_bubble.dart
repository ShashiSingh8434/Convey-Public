import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/chat_message_model.dart';
import '../pages/image_viewer_page.dart';
import 'message_status_widget.dart';

class ImageMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTimestamp;
  final int? otherUserLastReadTimestamp;

  const ImageMessageBubble({
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

  void _openViewer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerPage.network(imageUrl: message.content),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openViewer(context),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
            child: CachedNetworkImage(
              imageUrl: message.content,
              width: 220,
              height: 220,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 220,
                height: 220,
                color: const Color(0xFF1E2535),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 220,
                height: 220,
                color: const Color(0xFF1E2535),
                child: const Center(
                  child: Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white38,
                    size: 40,
                  ),
                ),
              ),
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

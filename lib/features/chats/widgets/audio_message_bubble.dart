import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../dialogs/audio_player_dialog.dart';
import '../models/chat_message_model.dart';
import 'message_status_widget.dart';

class AudioMessageBubble extends StatefulWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showTimestamp;
  final int? otherUserLastReadTimestamp;

  const AudioMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showTimestamp = false,
    this.otherUserLastReadTimestamp,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  // A lightweight player just for reading the duration for display.
  // The full player lives inside AudioPlayerDialog.
  final AudioPlayer _durationProbe = AudioPlayer();
  Duration? _totalDuration;
  bool _loadingDuration = true;

  @override
  void initState() {
    super.initState();
    _probeDuration();
  }

  @override
  void dispose() {
    _durationProbe.dispose();
    super.dispose();
  }

  Future<void> _probeDuration() async {
    try {
      final duration = await _durationProbe.setUrl(widget.message.content);
      if (mounted) {
        setState(() {
          _totalDuration = duration;
          _loadingDuration = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDuration = false);
    }
  }

  MessageStatus? get _status => computeStatus(
    isMine: widget.isMine,
    messageCreatedAt: widget.message.createdAt,
    otherUserLastReadTimestamp: widget.otherUserLastReadTimestamp,
  );

  void _openPlayer(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AudioPlayerDialog(audioUrl: widget.message.content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = _status;
    final bubbleColor = widget.isMine
        ? colorScheme.primary
        : const Color(0xFF1E2535);

    return Column(
      crossAxisAlignment: widget.isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _openPlayer(context),
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(widget.isMine ? 18 : 4),
                bottomRight: Radius.circular(widget.isMine ? 4 : 18),
              ),
            ),
            child: Row(
              children: [
                // Play button affordance
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Static waveform bars as a visual affordance
                      _WaveformBars(),
                      const SizedBox(height: 4),
                      _loadingDuration
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.white54,
                              ),
                            )
                          : Text(
                              _totalDuration != null
                                  ? _formatDuration(_totalDuration!)
                                  : '—',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.showTimestamp || status != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showTimestamp)
                  Text(
                    _formatTime(
                      DateTime.fromMillisecondsSinceEpoch(
                        widget.message.createdAt,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white24, fontSize: 11),
                  ),
                if (widget.showTimestamp && status != null)
                  const SizedBox(width: 4),
                MessageStatusWidget(status: status),
              ],
            ),
          ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Static waveform bars ──────────────────────────────────────────────────────

/// Decorative static waveform giving the voice note a distinctive shape.
class _WaveformBars extends StatelessWidget {
  // Arbitrary bar heights that look like a natural voice waveform.
  static const List<double> _heights = [
    4,
    8,
    12,
    6,
    14,
    10,
    16,
    8,
    12,
    6,
    10,
    14,
    8,
    6,
    12,
    10,
    8,
    4,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _heights.map((h) {
          return Container(
            width: 2.5,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }
}

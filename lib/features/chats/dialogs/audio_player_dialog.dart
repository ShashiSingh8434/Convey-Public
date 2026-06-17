import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Full-featured playback dialog for received voice notes.
///
/// Features: Play/Pause, Seek bar, Current + Total duration,
/// Playback speed selector, Close button.
///
/// Usage:
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (_) => AudioPlayerDialog(audioUrl: message.content),
/// );
/// ```
class AudioPlayerDialog extends StatefulWidget {
  final String audioUrl;

  const AudioPlayerDialog({super.key, required this.audioUrl});

  @override
  State<AudioPlayerDialog> createState() => _AudioPlayerDialogState();
}

class _AudioPlayerDialogState extends State<AudioPlayerDialog> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _loading = true;
  double _speed = 1.0;

  static const List<double> _speeds = [0.5, 1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final duration = await _player.setUrl(widget.audioUrl);
      if (mounted) {
        setState(() {
          _total = duration ?? Duration.zero;
          _loading = false;
        });
      }

      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state.playing);
          if (state.processingState == ProcessingState.completed) {
            _player.seek(Duration.zero);
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _cycleSpeed() async {
    final currentIndex = _speeds.indexOf(_speed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final next = _speeds[nextIndex];
    await _player.setSpeed(next);
    setState(() => _speed = next);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _speedLabel(double speed) {
    if (speed == 1.0) return '1×';
    if (speed == 0.5) return '0.5×';
    if (speed == 1.5) return '1.5×';
    return '2×';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalSeconds = _total.inSeconds.toDouble();
    final positionSeconds = _position.inSeconds.toDouble().clamp(
      0.0,
      totalSeconds > 0 ? totalSeconds : 1.0,
    );

    return Dialog(
      backgroundColor: const Color(0xFF1A2033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🎤  Voice Note',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Play / Pause
            GestureDetector(
              onTap: _loading ? null : _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Seek bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: Colors.white12,
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: positionSeconds,
                max: totalSeconds > 0 ? totalSeconds : 1.0,
                onChanged: _loading
                    ? null
                    : (value) {
                        _player.seek(Duration(seconds: value.toInt()));
                      },
              ),
            ),

            // Duration row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  Text(
                    _formatDuration(_total),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Speed selector
            GestureDetector(
              onTap: _loading ? null : _cycleSpeed,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _speedLabel(_speed),
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

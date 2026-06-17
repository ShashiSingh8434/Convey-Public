import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Shown immediately after a voice note recording completes.
///
/// The user can listen to the recording, then choose to Cancel (discard it)
/// or Send (returns `true` to the caller so the upload flow begins).
///
/// Usage:
/// ```dart
/// final shouldSend = await showDialog<bool>(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => AudioPreviewDialog(audioFile: file),
/// );
/// if (shouldSend == true) { /* start upload */ }
/// ```
class AudioPreviewDialog extends StatefulWidget {
  final File audioFile;

  const AudioPreviewDialog({super.key, required this.audioFile});

  @override
  State<AudioPreviewDialog> createState() => _AudioPreviewDialogState();
}

class _AudioPreviewDialogState extends State<AudioPreviewDialog> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final duration = await _player.setFilePath(widget.audioFile.path);
      setState(() {
        _total = duration ?? Duration.zero;
        _loading = false;
      });

      _player.positionStream.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });

      _player.playerStateStream.listen((state) {
        if (mounted) {
          setState(() => _isPlaying = state.playing);
          // Auto-reset to start when playback completes.
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

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalSeconds = _total.inSeconds.toDouble();
    final positionSeconds = _position.inSeconds.toDouble().clamp(
      0.0,
      totalSeconds.isFinite && totalSeconds > 0 ? totalSeconds : 1.0,
    );

    return Dialog(
      backgroundColor: const Color(0xFF1A2033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            const Text(
              'Voice Note',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),

            // Play / Pause button
            GestureDetector(
              onTap: _loading ? null : _togglePlay,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(16),
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
                        size: 30,
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Seek bar
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Send'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

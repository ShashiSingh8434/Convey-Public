import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/cloudinary_service.dart';
import '../dialogs/audio_preview_dialog.dart';
import '../pages/image_viewer_page.dart';
import '../providers/chat_providers.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../services/typing_service.dart';

/// The message composition bar at the bottom of [ChatPage].
///
/// Owns:
/// * Text input + send
/// * Image picking (gallery → preview → upload)
/// * Audio recording (hold → preview dialog → upload)
///
/// Business logic (picking, compression, validation, upload) is delegated to
/// [MediaService] and [CloudinaryService]. This widget only orchestrates the
/// flow and UI states.
class ChatInputBar extends ConsumerStatefulWidget {
  final String chatId;
  final String recipientUid;

  const ChatInputBar({
    super.key,
    required this.chatId,
    required this.recipientUid,
  });

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSending = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    TypingService.instance.clearTyping(widget.chatId);
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Text send ──────────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _inputController.clear();
    TypingService.instance.clearTyping(widget.chatId);

    try {
      await ChatService.instance.sendTextMessage(
        chatId: widget.chatId,

        recipientUid: widget.recipientUid,

        content: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message.')),
        );
        _inputController.text = text;
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // ── Image flow ─────────────────────────────────────────────────────────────

  Future<void> _pickAndSendImage() async {
    try {
      // 1. Pick from gallery
      final file = await MediaService.instance.pickImage();
      if (file == null) return; // user cancelled

      // 2. Validate original size (<10 MB)
      await MediaService.instance.validateImage(file);

      // 3. Compress
      final compressed = await MediaService.instance.compressImage(file);

      // 4. Open preview page — upload only happens when user taps Send
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImageViewerPage.preview(
            file: compressed,
            onSend: () => _uploadAndSendImage(compressed),
          ),
        ),
      );
    } on ImageTooLargeException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not pick image.')));
      }
    }
  }

  /// Called from [ImageViewerPage.preview] when the user taps Send.
  Future<void> _uploadAndSendImage(File compressed) async {
    // Pop the preview page first so the loading dialog can show on chat_page.
    if (mounted) Navigator.of(context).pop();

    final messageId = const Uuid().v4();

    _showUploadingDialog();

    try {
      // 5. Upload to Cloudinary
      final result = await CloudinaryService.instance.uploadImage(
        image: compressed,
        chatId: widget.chatId,
        messageId: messageId,
      );

      // 6. Write RTDB message + update Firestore
      await ChatService.instance.sendImageMessage(
        chatId: widget.chatId,
        recipientUid: widget.recipientUid,
        messageId: messageId,
        imageUrl: result.url,
      );

      if (mounted) Navigator.of(context).pop(); // dismiss loading dialog
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send photo: $e')));
      }
    }
  }

  // ── Audio flow ─────────────────────────────────────────────────────────────

  Future<void> _handleMicTap() async {
    final isRecording = ref.read(recordingStateProvider(widget.chatId));

    if (!isRecording) {
      await _startRecording();
    } else {
      await _stopAndPreviewAudio();
    }
  }

  Future<void> _startRecording() async {
    try {
      await MediaService.instance.startRecording();
      ref.read(recordingStateProvider(widget.chatId).notifier).state = true;
    } on MediaServiceException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _stopAndPreviewAudio() async {
    final file = await MediaService.instance.stopRecording();
    ref.read(recordingStateProvider(widget.chatId).notifier).state = false;

    if (file == null || !mounted) return;

    // Open preview dialog — upload only if user confirms
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AudioPreviewDialog(audioFile: file),
    );

    if (shouldSend == true) {
      await _uploadAndSendAudio(file);
    }
  }

  Future<void> _uploadAndSendAudio(File audioFile) async {
    final messageId = const Uuid().v4();

    _showUploadingDialog();

    try {
      // Upload to Cloudinary (video resource type)
      final result = await CloudinaryService.instance.uploadAudio(
        audio: audioFile,
        chatId: widget.chatId,
        messageId: messageId,
      );

      // Write RTDB message + update Firestore
      await ChatService.instance.sendAudioMessage(
        chatId: widget.chatId,
        recipientUid: widget.recipientUid,
        messageId: messageId,
        audioUrl: result.url,
      );

      if (mounted) Navigator.of(context).pop(); // dismiss loading dialog
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice note: $e')),
        );
      }
    }
  }

  // ── Shared upload loading dialog ───────────────────────────────────────────

  void _showUploadingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Color(0xFF1A2033),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(width: 20),
              Text(
                'Sending…',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isRecording = ref.watch(recordingStateProvider(widget.chatId));

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0F17),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Image icon ──
          if (!isRecording)
            _CircleIconButton(
              icon: Icons.image_rounded,
              onTap: _isSending ? null : _pickAndSendImage,
              color: Colors.white38,
            ),

          if (!isRecording) const SizedBox(width: 4),

          // ── Text field ──
          if (!isRecording)
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2535),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Message',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (text) {
                    TypingService.instance.onTextChanged(widget.chatId, text);
                    // Rebuild to toggle send / mic button.
                    setState(() {});
                  },
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),

          // ── Recording indicator ──
          if (isRecording)
            Expanded(
              child: _RecordingIndicator(
                onCancel: () async {
                  await MediaService.instance.cancelRecording();
                  ref
                          .read(recordingStateProvider(widget.chatId).notifier)
                          .state =
                      false;
                },
              ),
            ),

          const SizedBox(width: 8),

          // ── Send / mic button ──
          AnimatedBuilder(
            animation: _inputController,
            builder: (context, _) {
              final hasText = _inputController.text.trim().isNotEmpty;

              if (isRecording) {
                // Show a stop button while recording.
                return _CircleIconButton(
                  icon: Icons.stop_rounded,
                  onTap: _stopAndPreviewAudio,
                  color: Colors.redAccent,
                  filled: true,
                );
              }

              if (hasText) {
                // Send text button.
                return AnimatedScale(
                  scale: 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: GestureDetector(
                    onTap: _isSending ? null : _sendText,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                );
              }

              // Mic button when text field is empty.
              return _CircleIconButton(
                icon: Icons.mic_rounded,
                onTap: _handleMicTap,
                color: Colors.white,
                filled: true,
                fillColor: colorScheme.primary.withValues(alpha: 0.3),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Recording indicator ───────────────────────────────────────────────────────

class _RecordingIndicator extends StatefulWidget {
  final VoidCallback onCancel;
  const _RecordingIndicator({required this.onCancel});

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FadeTransition(
          opacity: _blink,
          child: const Icon(
            Icons.fiber_manual_record,
            color: Colors.red,
            size: 14,
          ),
        ),
        const SizedBox(width: 8),
        const Text(
          'Recording…',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        GestureDetector(
          onTap: widget.onCancel,
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Reusable circle icon button ───────────────────────────────────────────────

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool filled;
  final Color? fillColor;

  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    required this.color,
    this.filled = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: filled
              ? (fillColor ?? Colors.transparent)
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

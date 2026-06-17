import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ── Mode ──────────────────────────────────────────────────────────────────────

enum _ImageViewerMode { preview, viewer }

// ── Page ──────────────────────────────────────────────────────────────────────

/// A full-screen image page with two modes:
///
/// **Preview mode** — shows a local [File] before sending.
/// The user can tap Cancel to go back or Send to trigger the [onSend] callback.
///
/// **Viewer mode** — shows a Cloudinary URL for a received image.
/// The user can tap Close to dismiss.
///
/// Use the named constructors [ImageViewerPage.preview] and
/// [ImageViewerPage.network] rather than the default constructor.
class ImageViewerPage extends StatelessWidget {
  final _ImageViewerMode _mode;

  // Preview mode fields
  final File? _file;
  final VoidCallback? _onSend;

  // Viewer mode fields
  final String? _imageUrl;

  const ImageViewerPage._({
    required _ImageViewerMode mode,
    File? file,
    VoidCallback? onSend,
    String? imageUrl,
  }) : _mode = mode,
       _file = file,
       _onSend = onSend,
       _imageUrl = imageUrl;

  /// Preview mode: show a local file before sending.
  ///
  /// [onSend] is called when the user confirms — the caller is responsible for
  /// the actual upload flow.
  factory ImageViewerPage.preview({
    required File file,
    required VoidCallback onSend,
  }) {
    return ImageViewerPage._(
      mode: _ImageViewerMode.preview,
      file: file,
      onSend: onSend,
    );
  }

  /// Viewer mode: show a received image from a network URL.
  factory ImageViewerPage.network({required String imageUrl}) {
    return ImageViewerPage._(mode: _ImageViewerMode.viewer, imageUrl: imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: _buildBody(),
      bottomNavigationBar: _mode == _ImageViewerMode.preview
          ? _PreviewActionBar(onSend: _onSend!)
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        _mode == _ImageViewerMode.preview ? 'Send Photo' : '',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == _ImageViewerMode.preview) {
      return PhotoView(
        imageProvider: FileImage(_file!),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      );
    }

    return PhotoView(
      imageProvider: CachedNetworkImageProvider(_imageUrl!),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }
}

// ── Preview action bar ────────────────────────────────────────────────────────

class _PreviewActionBar extends StatelessWidget {
  final VoidCallback onSend;

  const _PreviewActionBar({required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0B0F17),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
          ElevatedButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

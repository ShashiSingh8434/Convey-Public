import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

/// Maximum original image size accepted before compression: 10 MB.
const int kMaxImageBytes = 10 * 1024 * 1024;

/// Quality passed to flutter_image_compress (0–100).
const int kImageCompressQuality = 80;

// ── Exceptions ────────────────────────────────────────────────────────────────

class ImageTooLargeException implements Exception {
  final int bytes;
  const ImageTooLargeException(this.bytes);

  @override
  String toString() =>
      'Image is too large (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB). '
      'Maximum allowed size is ${kMaxImageBytes ~/ (1024 * 1024)} MB.';
}

class MediaServiceException implements Exception {
  final String message;
  const MediaServiceException(this.message);

  @override
  String toString() => message;
}

// ── Service ───────────────────────────────────────────────────────────────────

class MediaService {
  MediaService._();
  static final instance = MediaService._();

  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  // ── Image ──────────────────────────────────────────────────────────────────

  /// Opens the device gallery and returns the selected [File],
  /// or `null` if the user cancelled.
  Future<File?> pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // We compress manually below.
    );

    if (picked == null) return null;
    return File(picked.path);
  }

  /// Validates that [image] does not exceed [kMaxImageBytes].
  ///
  /// Throws [ImageTooLargeException] if the file is too large.
  Future<void> validateImage(File image) async {
    final bytes = await image.length();
    if (bytes > kMaxImageBytes) {
      throw ImageTooLargeException(bytes);
    }
  }

  /// Compresses [image] using flutter_image_compress.
  ///
  /// Returns the compressed [File] written to the app's temp directory.
  /// The output format is JPEG.
  Future<File> compressImage(File image) async {
    final dir = await getTemporaryDirectory();
    final targetPath =
        '${dir.path}/convey_compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      image.absolute.path,
      targetPath,
      quality: kImageCompressQuality,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      throw const MediaServiceException(
        'Image compression failed — null result returned.',
      );
    }

    return File(result.path);
  }

  // ── Audio ──────────────────────────────────────────────────────────────────

  /// Requests microphone permission and starts recording.
  ///
  /// The recording is written to the app's temp directory as an M4A file.
  /// Throws [MediaServiceException] if permission is denied or recording fails.
  Future<void> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw const MediaServiceException(
        'Microphone permission denied. '
        'Please enable it in your device settings.',
      );
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/convey_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
      ),
      path: path,
    );
  }

  /// Stops an active recording and returns the recorded [File].
  ///
  /// Returns `null` if the recorder was not active.
  Future<File?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  /// Returns `true` if a recording is currently in progress.
  Future<bool> get isRecording => _recorder.isRecording();

  /// Cancels an active recording without saving.
  Future<void> cancelRecording() async {
    await _recorder.cancel();
  }

  // /// Disposes the recorder. Call when the owning widget is disposed.
  // Future<void> disposeRecorder() async {
  //   await _recorder.dispose();
  // }
}

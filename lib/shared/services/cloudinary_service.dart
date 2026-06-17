import 'dart:io';

import 'package:http/http.dart' as http;
import 'dart:convert';

// ── Result type ───────────────────────────────────────────────────────────────

class CloudinaryUploadResult {
  final String url;
  final String publicId;

  const CloudinaryUploadResult({required this.url, required this.publicId});
}

// ── Service ───────────────────────────────────────────────────────────────────

class CloudinaryService {
  CloudinaryService._();
  static final instance = CloudinaryService._();

  // ── ⚙️  Configure these two values ────────────────────────────────────────
  static const String _cloudName = '*****';
  static const String _uploadPreset = '*****';
  static const String _uploadPresetChat = '*****';
  // ──────────────────────────────────────────────────────────────────────────

  // ── Profile photo (unchanged) ─────────────────────────────────────────────

  static const String _profileFolder = '*****';
  // static const String _chatFolder = 'convey_chat';

  Uri get _imageUploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

  Uri get _videoUploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/video/upload');

  /// Uploads [file] to the profile photos folder.
  /// Returns the permanent secure URL.
  /// Kept for backward compatibility with profile photo upload.
  Future<String> uploadFile(File file) async {
    _assertConfigured();

    try {
      final request = http.MultipartRequest('POST', _imageUploadUri)
        ..fields['upload_preset'] = _uploadPreset
        ..fields['folder'] = _profileFolder
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        throw CloudinaryUploadException(
          'Upload failed (HTTP ${streamedResponse.statusCode}): $body',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      if (json['secure_url'] == null) {
        throw CloudinaryUploadException(
          'Cloudinary response missing secure_url: $body',
        );
      }

      return json['secure_url'] as String;
    } on CloudinaryUploadException {
      rethrow;
    } catch (e) {
      throw CloudinaryUploadException('Unexpected upload error: $e');
    }
  }

  // ── Chat image upload ─────────────────────────────────────────────────────

  /// Uploads a chat image to `convey_chat_images/{chatId}/{messageId}.jpg`.
  ///
  /// Uses the `image/upload` Cloudinary endpoint.
  /// Returns [CloudinaryUploadResult] containing the secure URL and public ID.
  Future<CloudinaryUploadResult> uploadImage({
    required File image,
    required String chatId,
    required String messageId,
  }) async {
    _assertConfigured();

    final publicId = 'convey_chat_images/$chatId/$messageId';

    try {
      final request = http.MultipartRequest('POST', _imageUploadUri)
        ..fields['upload_preset'] = _uploadPresetChat
        ..fields['public_id'] = publicId
        ..files.add(await http.MultipartFile.fromPath('file', image.path));

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        throw CloudinaryUploadException(
          'Image upload failed (HTTP ${streamedResponse.statusCode}): $body',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      final url = json['secure_url'] as String?;
      final returnedPublicId = json['public_id'] as String?;

      if (url == null || returnedPublicId == null) {
        throw CloudinaryUploadException(
          'Cloudinary image response missing fields: $body',
        );
      }

      return CloudinaryUploadResult(url: url, publicId: returnedPublicId);
    } on CloudinaryUploadException {
      rethrow;
    } catch (e) {
      throw CloudinaryUploadException('Unexpected image upload error: $e');
    }
  }

  // ── Chat audio upload ─────────────────────────────────────────────────────

  /// Uploads a voice note to `convey_chat_audio/{chatId}/{messageId}.m4a`.
  ///
  /// Uses the `video/upload` Cloudinary endpoint — Cloudinary stores audio
  /// files under the video resource type.
  /// Returns [CloudinaryUploadResult] containing the secure URL and public ID.
  Future<CloudinaryUploadResult> uploadAudio({
    required File audio,
    required String chatId,
    required String messageId,
  }) async {
    _assertConfigured();

    final publicId = 'convey_chat_audio/$chatId/$messageId';

    try {
      final request = http.MultipartRequest('POST', _videoUploadUri)
        ..fields['upload_preset'] = _uploadPresetChat
        ..fields['public_id'] = publicId
        ..fields['resource_type'] = 'video'
        ..files.add(await http.MultipartFile.fromPath('file', audio.path));

      final streamedResponse = await request.send();
      final body = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        throw CloudinaryUploadException(
          'Audio upload failed (HTTP ${streamedResponse.statusCode}): $body',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;

      final url = json['secure_url'] as String?;
      final returnedPublicId = json['public_id'] as String?;

      if (url == null || returnedPublicId == null) {
        throw CloudinaryUploadException(
          'Cloudinary audio response missing fields: $body',
        );
      }

      return CloudinaryUploadResult(url: url, publicId: returnedPublicId);
    } on CloudinaryUploadException {
      rethrow;
    } catch (e) {
      throw CloudinaryUploadException('Unexpected audio upload error: $e');
    }
  }

  // ── Deletion (server-side only) ───────────────────────────────────────────

  /// Deletion requires a signed request.
  /// Implement via a Firebase Cloud Function for production use.
  Future<void> deleteFile(String publicId) async {
    throw UnimplementedError(
      'Client-side deletion requires signed requests. '
      'Use a Cloud Function instead.',
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _assertConfigured() {
    if (_cloudName == 'YOUR_CLOUD_NAME' ||
        _uploadPreset == 'YOUR_UPLOAD_PRESET') {
      throw CloudinaryUploadException(
        'CloudinaryService is not configured.\n'
        'Open cloudinary_service.dart and set _cloudName and _uploadPreset.',
      );
    }
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class CloudinaryUploadException implements Exception {
  final String message;
  const CloudinaryUploadException(this.message);

  @override
  String toString() => message;
}

import 'dart:io';

import 'package:convey/features/profile/widgets/social_details_edit_tile.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/providers.dart';
import '../models/user_model.dart';
import '../../../shared/services/cloudinary_service.dart';
import '../services/user_service.dart';
import '../../profile/widgets/profile_avatar.dart';

class ProfileSetupPage extends ConsumerStatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  ConsumerState<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends ConsumerState<ProfileSetupPage> {
  final _pageController = PageController();
  int _currentStage = 0;

  // Stage 1
  File? _pickedImage;
  bool _uploadingPhoto = false;
  String? _uploadedPhotoUrl; // set after successful Cloudinary upload
  bool _showUploadButtons = false;

  // Stage 2
  late final TextEditingController _displayNameController;
  late final TextEditingController _aboutController;
  bool _savingProfile = false;

  // Stage 3
  final _githubController = TextEditingController();
  final _instagramController = TextEditingController();
  final _linkedinController = TextEditingController();
  bool _savingSocial = false;

  AppUser? _appUser;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _aboutController = TextEditingController(
      text: 'Hey there I am using Convey !!!',
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    _aboutController.dispose();
    _githubController.dispose();
    _instagramController.dispose();
    _linkedinController.dispose();
    super.dispose();
  }

  void _prefillFromUser(AppUser user) {
    if (_prefilled) return;
    _prefilled = true;
    _appUser = user;
    _displayNameController.text = user.profile.displayName?.isNotEmpty == true
        ? user.profile.displayName!
        : user.username ?? '';
    _aboutController.text = user.profile.about?.isNotEmpty == true
        ? user.profile.about!
        : 'Hey there I am using Convey !!!';
    _uploadedPhotoUrl = user.profile.photoUrl;
    _githubController.text = user.social.github ?? '';
    _instagramController.text = user.social.instagram ?? '';
    _linkedinController.text = user.social.linkedin ?? '';
  }

  void _nextStage() {
    final next = _currentStage + 1;
    setState(() => _currentStage = next);
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // ── Stage 1: Pick & Upload Photo ──────────────────────────────────────────

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked != null) {
      setState(() {
        _pickedImage = File(picked.path);
        _showUploadButtons = true;
      });
    }
  }

  Future<void> _uploadPhoto() async {
    if (_pickedImage == null) return;
    try {
      setState(() => _uploadingPhoto = true);

      final url = await CloudinaryService.instance.uploadFile(_pickedImage!);

      // Persist immediately so the URL survives app restarts
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.instance.updateProfile(
        uid: uid,
        profile: (_appUser?.profile ?? const UserProfile()).copyWith(
          photoUrl: url,
        ),
      );

      setState(() {
        _uploadedPhotoUrl = url;
        _showUploadButtons = false;
        _pickedImage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo updated!'),
            backgroundColor: Colors.green,
          ),
        );

        ref.watch(userDocumentProvider).whenData((user) {
          if (user != null) _prefillFromUser(user);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Stage 2: Save Profile Info ────────────────────────────────────────────

  Future<void> _saveProfileInfo() async {
    final displayName = _displayNameController.text.trim();
    final about = _aboutController.text.trim();

    if (displayName.isEmpty) {
      _showError('Display name is required.');
      return;
    }
    if (about.isEmpty) {
      _showError('About is required.');
      return;
    }
    if (about.length > 150) {
      _showError('About must be 150 characters or less.');
      return;
    }

    try {
      setState(() => _savingProfile = true);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.instance.updateProfile(
        uid: uid,
        profile: (_appUser?.profile ?? const UserProfile()).copyWith(
          displayName: displayName,
          about: about,
          photoUrl: _uploadedPhotoUrl,
        ),
      );
      _nextStage();
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  // ── Stage 3: Save Social + Complete ──────────────────────────────────────

  Future<void> _saveSocialAndFinish() async {
    final github = _githubController.text.trim();
    final instagram = _instagramController.text.trim();
    final linkedin = _linkedinController.text.trim();

    // Guard: reject full URLs
    for (final entry in {
      'GitHub': github,
      'Instagram': instagram,
      'LinkedIn': linkedin,
    }.entries) {
      if (entry.value.contains('/') || entry.value.contains('http')) {
        _showError('${entry.key}: enter only your username, not the full URL.');
        return;
      }
    }

    try {
      setState(() => _savingSocial = true);
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Single write: social + profileCompleted = true
      await UserService.instance.completeOnboarding(
        uid: uid,
        profile: (_appUser?.profile ?? const UserProfile()).copyWith(
          displayName: _displayNameController.text.trim(),
          about: _aboutController.text.trim(),
          photoUrl: _uploadedPhotoUrl,
        ),
        social: UserSocial(
          github: github.isEmpty ? null : github,
          instagram: instagram.isEmpty ? null : instagram,
          linkedin: linkedin.isEmpty ? null : linkedin,
        ),
      );

      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _savingSocial = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pre-fill once when user doc arrives
    ref.watch(userDocumentProvider).whenData((user) {
      if (user != null) _prefillFromUser(user);
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0B0F17), Color(0xFF121826), Color(0xFF0B0F17)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 450,
                    maxHeight: 650,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _StageHeader(
                          currentStage: _currentStage,
                          stages: const ['Photo', 'Profile', 'Social'],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _PhotoStage(
                              pickedImage: _pickedImage,
                              uploadedPhotoUrl: _uploadedPhotoUrl,
                              showUploadButtons: _showUploadButtons,
                              uploading: _uploadingPhoto,
                              onPickImage: _pickImage,
                              onUpload: _uploadPhoto,
                              onCancel: () => setState(() {
                                _pickedImage = null;
                                _showUploadButtons = false;
                              }),
                              onNext: _nextStage,
                            ),

                            _ProfileInfoStage(
                              displayNameController: _displayNameController,
                              aboutController: _aboutController,
                              saving: _savingProfile,
                              onSave: _saveProfileInfo,
                            ),
                            _SocialStage(
                              githubController: _githubController,
                              instagramController: _instagramController,
                              linkedinController: _linkedinController,
                              saving: _savingSocial,
                              onSave: _saveSocialAndFinish,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAGE HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _StageHeader extends StatelessWidget {
  final int currentStage;
  final List<String> stages;
  const _StageHeader({required this.currentStage, required this.stages});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: stages.asMap().entries.map((entry) {
        final i = entry.key;
        final label = entry.value;
        final active = i == currentStage;
        final done = i < currentStage;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 4,
                      decoration: BoxDecoration(
                        color: done || active
                            ? colorScheme.primary
                            : Colors.white12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: active
                            ? colorScheme.primary
                            : done
                            ? Colors.white54
                            : Colors.white24,
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < stages.length - 1) const SizedBox(width: 8),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAGE 1 – PHOTO
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoStage extends StatelessWidget {
  final File? pickedImage;
  final String? uploadedPhotoUrl;
  final bool showUploadButtons;
  final bool uploading;
  final VoidCallback onPickImage;
  final VoidCallback onUpload;
  final VoidCallback onCancel;
  final VoidCallback onNext;

  const _PhotoStage({
    required this.pickedImage,
    required this.uploadedPhotoUrl,
    required this.showUploadButtons,
    required this.uploading,
    required this.onPickImage,
    required this.onUpload,
    required this.onCancel,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text(
                'Profile Photo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This is how others will see you.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: 40),
              ProfileAvatar(
                imageFile: pickedImage,
                photoUrl: uploadedPhotoUrl,
                radius: 64,
              ),
              const SizedBox(height: 32),
              if (!showUploadButtons) ...[
                OutlinedButton.icon(
                  onPressed: onPickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Change Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(200, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: uploading ? null : onUpload,
                      icon: uploading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(uploading ? 'Uploading...' : 'Upload'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: uploading ? null : onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (showUploadButtons) {
                      final proceed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1F2533),
                          title: const Text(
                            'Unsaved Photo',
                            style: TextStyle(color: Colors.white),
                          ),
                          content: const Text(
                            'You selected a new profile photo but have not uploaded it yet.',
                            style: TextStyle(color: Colors.white70),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Skip'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Stay'),
                            ),
                          ],
                        ),
                      );

                      if (proceed != true) return;
                    }

                    onNext();
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAGE 2 – PROFILE INFO
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileInfoStage extends StatelessWidget {
  final TextEditingController displayNameController;
  final TextEditingController aboutController;
  final bool saving;
  final VoidCallback onSave;

  const _ProfileInfoStage({
    required this.displayNameController,
    required this.aboutController,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your profile',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This information will be visible to others.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 28),
            _DarkTextField(
              label: 'Display Name *',
              controller: displayNameController,
              hint: 'Your display name',
            ),
            const SizedBox(height: 16),
            _DarkTextField(
              label: 'About *',
              controller: aboutController,
              hint: 'Hey there I am using Convey !!!',
              maxLines: 3,
              maxLength: 150,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save & Next',
                        style: TextStyle(
                          fontSize: 16,
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

// ─────────────────────────────────────────────────────────────────────────────
// STAGE 3 – SOCIAL
// ─────────────────────────────────────────────────────────────────────────────

class _SocialStage extends StatelessWidget {
  final TextEditingController githubController;
  final TextEditingController instagramController;
  final TextEditingController linkedinController;
  final bool saving;
  final VoidCallback onSave;

  const _SocialStage({
    required this.githubController,
    required this.instagramController,
    required this.linkedinController,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Social Links',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Optional — enter only your username, not the full URL.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white60,
              ),
            ),
            const SizedBox(height: 28),
            SocialEditField(
              controller: githubController,
              icon: Icons.code,
              label: 'GitHub',
              hint: 'e.g. shashi',
              prefix: 'github.com/',
            ),
            const SizedBox(height: 16),
            SocialEditField(
              controller: instagramController,
              icon: Icons.camera_alt_outlined,
              label: 'Instagram',
              hint: 'e.g. shashi_dev',
              prefix: 'instagram.com/',
            ),
            const SizedBox(height: 16),
            SocialEditField(
              controller: linkedinController,
              icon: Icons.work_outline,
              label: 'LinkedIn',
              hint: 'e.g. shashi-singh',
              prefix: 'linkedin.com/in/',
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : onSave,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save & Go to Dashboard',
                        style: TextStyle(
                          fontSize: 16,
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

// ─────────────────────────────────────────────────────────────────────────────
// SHARED FORM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _DarkTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final bool readOnly;
  final int maxLines;
  final int? maxLength;

  const _DarkTextField({
    required this.label,
    this.hint,
    this.controller,
    this.readOnly = false,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          maxLength: maxLength,
          style: TextStyle(color: readOnly ? Colors.white38 : Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white30),
            filled: true,
            fillColor: readOnly
                ? const Color(0xFF161B26)
                : const Color(0xFF1F2533),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary),
            ),
            counterStyle: const TextStyle(color: Colors.white38),
          ),
        ),
      ],
    );
  }
}

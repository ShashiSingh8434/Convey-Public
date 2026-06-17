import 'dart:io';

import 'package:convey/shared/widgets/loading_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../onboarding/models/user_model.dart';
import '../../../shared/services/cloudinary_service.dart';
import '../../onboarding/services/user_service.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_field.dart';
import '../widgets/social_details_edit_tile.dart';
import '../widgets/social_link_tile.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  // Controllers
  late final TextEditingController _displayNameController;
  late final TextEditingController _aboutController;
  late final TextEditingController _githubController;
  late final TextEditingController _instagramController;
  late final TextEditingController _linkedinController;

  // State
  bool _prefilled = false;
  bool _editing = false;
  bool _uploadingPhoto = false;
  bool _saving = false;
  String? _currentPhotoUrl;
  File? _pendingPhotoFile;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _aboutController = TextEditingController();
    _githubController = TextEditingController();
    _instagramController = TextEditingController();
    _linkedinController = TextEditingController();
  }

  @override
  void dispose() {
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
    _displayNameController.text = user.profile.displayName ?? '';
    _aboutController.text = user.profile.about ?? '';
    _githubController.text = user.social.github ?? '';
    _instagramController.text = user.social.instagram ?? '';
    _linkedinController.text = user.social.linkedin ?? '';
    _currentPhotoUrl = user.profile.photoUrl;
  }

  // ── Photo ─────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null) return;

    final file = File(picked.path);
    setState(() => _pendingPhotoFile = file);

    try {
      setState(() => _uploadingPhoto = true);
      final url = await CloudinaryService.instance.uploadFile(file);
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Update photo immediately, independent of the Save button
      final current = ref.read(userDocumentProvider).value;
      await UserService.instance.updateProfile(
        uid: uid,
        profile: (current?.profile ?? const UserProfile()).copyWith(
          photoUrl: url,
        ),
      );

      setState(() {
        _currentPhotoUrl = url;
        _pendingPhotoFile = null;
      });

      if (mounted) AppSnackbar.success(context, 'Photo updated!');
    } catch (e) {
      setState(() => _pendingPhotoFile = null);
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  // ── Save profile edits ────────────────────────────────────────────────────

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    final about = _aboutController.text.trim();
    final github = _githubController.text.trim();
    final instagram = _instagramController.text.trim();
    final linkedin = _linkedinController.text.trim();

    if (displayName.isEmpty) {
      AppSnackbar.error(context, 'Display name cannot be empty.');
      return;
    }
    if (about.isEmpty) {
      AppSnackbar.error(context, 'About cannot be empty.');
      return;
    }
    if (about.length > 150) {
      AppSnackbar.error(context, 'About must be 150 characters or less.');
      return;
    }
    for (final entry in {
      'GitHub': github,
      'Instagram': instagram,
      'LinkedIn': linkedin,
    }.entries) {
      if (entry.value.contains('/') || entry.value.contains('http')) {
        AppSnackbar.error(
          context,
          '${entry.key}: enter only your username, not the full URL.',
        );
        return;
      }
    }

    try {
      setState(() => _saving = true);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final current = ref.read(userDocumentProvider).value;

      // Single write: profile + social together
      await UserService.instance.updateUserFields(
        uid: uid,
        fields: {
          'profile': (current?.profile ?? const UserProfile())
              .copyWith(
                displayName: displayName,
                about: about,
                photoUrl: _currentPhotoUrl,
              )
              .toMap(),
          'social': UserSocial(
            github: github.isEmpty ? null : github,
            instagram: instagram.isEmpty ? null : instagram,
            linkedin: linkedin.isEmpty ? null : linkedin,
          ).toMap(),
        },
      );

      if (mounted) {
        setState(() => _editing = false);
        AppSnackbar.success(context, 'Profile saved!');
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final userAsync = ref.watch(userDocumentProvider);

    userAsync.whenData((user) {
      if (user != null) _prefillFromUser(user);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F17),
        foregroundColor: Colors.white,
        title: const Text('My Profile'),
        actions: [
          if (!_editing)
            TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(
                Icons.edit_outlined,
                color: Colors.white70,
                size: 18,
              ),
              label: const Text(
                'Edit',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else ...[
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      // Revert fields from live Firestore data
                      _prefilled = false;
                      final user = userAsync.value;
                      if (user != null) _prefillFromUser(user);
                      setState(() => _editing = false);
                    },
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Save',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ],
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text(
                'No profile data.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Avatar + change button ──────────────────────────────
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        ProfileAvatar(
                          imageFile: _pendingPhotoFile,
                          photoUrl: _currentPhotoUrl,
                          displayName: user.profile.displayName,
                          radius: 56,
                        ),
                        GestureDetector(
                          onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF0B0F17),
                                width: 2,
                              ),
                            ),
                            child: _uploadingPhoto
                                ? const SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Username (always read-only) ─────────────────────────
                    Text(
                      '@${user.username ?? ''}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),

                    if (!_editing) ...[
                      const SizedBox(height: 14),
                      Text(
                        user.profile.displayName ?? 'Unknown User',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ── Editable fields ────────────────────────────────────
                    if (_editing) ...[
                      const SizedBox(height: 28),
                      ProfileField(
                        label: 'Display Name',
                        controller: _displayNameController,
                        editing: _editing,
                        hint: 'Your display name',
                      ),
                    ],
                    const SizedBox(height: 16),
                    ProfileField(
                      label: 'About',
                      controller: _aboutController,
                      editing: _editing,
                      hint: 'Tell others about yourself',
                      maxLines: 3,
                      maxLength: _editing ? 150 : null,
                    ),

                    const SizedBox(height: 24),

                    // ── Social section ─────────────────────────────────────
                    _SectionLabel('Social Links'),
                    const SizedBox(height: 12),

                    if (_editing) ...[
                      SocialEditField(
                        controller: _githubController,
                        icon: Icons.code,
                        label: 'GitHub',
                        hint: 'e.g. shashi',
                        prefix: 'github.com/',
                      ),
                      const SizedBox(height: 12),
                      SocialEditField(
                        controller: _instagramController,
                        icon: Icons.camera_alt_outlined,
                        label: 'Instagram',
                        hint: 'e.g. shashi_dev',
                        prefix: 'instagram.com/',
                      ),
                      const SizedBox(height: 12),
                      SocialEditField(
                        controller: _linkedinController,
                        icon: Icons.work_outline,
                        label: 'LinkedIn',
                        hint: 'e.g. shashi-singh',
                        prefix: 'linkedin.com/in/',
                      ),
                    ] else ...[
                      if (!_hasSocial(user.social))
                        const Text(
                          'No social links added yet.',
                          style: TextStyle(color: Colors.white38, fontSize: 13),
                        )
                      else ...[
                        SocialLinkTile(
                          icon: Icons.code,
                          label: 'GitHub',
                          username: user.social.github,
                          urlPrefix: 'https://github.com/',
                        ),
                        SocialLinkTile(
                          icon: Icons.camera_alt_outlined,
                          label: 'Instagram',
                          username: user.social.instagram,
                          urlPrefix: 'https://instagram.com/',
                        ),
                        SocialLinkTile(
                          icon: Icons.work_outline,
                          label: 'LinkedIn',
                          username: user.social.linkedin,
                          urlPrefix: 'https://linkedin.com/in/',
                        ),
                      ],
                    ],

                    // ── Save button (visible only while editing) ───────────
                    if (_editing) ...[
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const AppLoadingScreen(),
        error: (e, _) => Center(
          child: Text(
            e.toString(),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ),
    );
  }

  bool _hasSocial(UserSocial social) =>
      (social.github?.isNotEmpty == true) ||
      (social.instagram?.isNotEmpty == true) ||
      (social.linkedin?.isNotEmpty == true);
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE FIELD WIDGETS (profile-page scoped)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

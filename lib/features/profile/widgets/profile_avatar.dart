import 'dart:io';
import 'package:flutter/material.dart';

/// Reusable avatar widget used in onboarding and profile page.
/// Priority: [imageFile] > [photoUrl] > initials from [displayName] > fallback icon.
class ProfileAvatar extends StatelessWidget {
  final File? imageFile;
  final String? photoUrl;
  final String? displayName;
  final double radius;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    this.imageFile,
    this.photoUrl,
    this.displayName,
    this.radius = 40,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    ImageProvider? image;
    if (imageFile != null) {
      image = FileImage(imageFile!);
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      image = NetworkImage(photoUrl!);
    }

    Widget child;
    if (image != null) {
      child = CircleAvatar(radius: radius, backgroundImage: image);
    } else {
      final initials = _initials(displayName);
      child = CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          initials,
          style: TextStyle(
            fontSize: radius * 0.45,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}

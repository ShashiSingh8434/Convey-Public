import 'package:flutter/material.dart';

class SocialEditField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String label;
  final String hint;
  final String prefix;

  const SocialEditField({
    super.key,
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    required this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, color: Colors.white38, size: 18),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white38),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        helperText: prefix,
        helperStyle: const TextStyle(color: Colors.white24, fontSize: 11),
        filled: true,
        fillColor: const Color(0xFF1F2533),
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
      ),
    );
  }
}

import 'package:flutter/material.dart';

class AppSnackbar {
  AppSnackbar._();

  static void success(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: Colors.green,
      icon: Icons.check_circle_rounded,
    );
  }

  static void error(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: Colors.red,
      icon: Icons.error_rounded,
    );
  }

  static void info(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: Colors.blue,
      icon: Icons.info_rounded,
    );
  }

  static void warning(BuildContext context, String message) {
    _show(
      context,
      message,
      backgroundColor: Colors.orange,
      icon: Icons.warning_rounded,
    );
  }

  static void _show(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    required IconData icon,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }
}

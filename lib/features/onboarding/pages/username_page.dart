import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/onboarding_providers.dart';
import '../services/user_service.dart';

class UsernamePage extends ConsumerStatefulWidget {
  const UsernamePage({super.key});

  @override
  ConsumerState<UsernamePage> createState() => _UsernamePageState();
}

class _UsernamePageState extends ConsumerState<UsernamePage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _debouncedUsername = '';
  Timer? _debounce;
  bool _formatValid = false;
  bool _submitted = false;
  bool _saving = false;

  static final _usernameRegex = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim().toLowerCase();
    final valid = _usernameRegex.hasMatch(trimmed);
    setState(() {
      _formatValid = valid;
      if (!valid) _debouncedUsername = '';
    });
    if (valid) {
      _debounce = Timer(const Duration(milliseconds: 500), () {
        setState(() => _debouncedUsername = trimmed);
      });
    }
  }

  String? _formatError(String value) {
    if (value.isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.length < 3) return 'Too short (min 3 characters)';
    if (trimmed.length > 20) return 'Too long (max 20 characters)';
    if (!RegExp(r'^[a-z]').hasMatch(trimmed.toLowerCase())) {
      return 'Must start with a letter';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(trimmed.toLowerCase())) {
      return 'Only lowercase letters, digits, and underscores';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final username = _controller.text.trim();
    if (!_formatValid) return;

    final available = await ref.read(
      usernameAvailabilityProvider(username.toLowerCase()).future,
    );
    if (!available) return;

    try {
      setState(() => _saving = true);
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await UserService.instance.claimUsername(uid: uid, username: username);
      if (mounted) context.go('/onboarding/profile');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rawValue = _controller.text.trim();
    final formatError = _submitted ? _formatError(rawValue) : null;

    final availabilityAsync = _debouncedUsername.isNotEmpty
        ? ref.watch(usernameAvailabilityProvider(_debouncedUsername))
        : null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // resizeToAvoidBottomInset: false,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Step indicator ──
                      _StepIndicator(current: 1, total: 2),

                      const SizedBox(height: 32),

                      // ── Warning banner ──
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.amber,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Usernames cannot be changed later. Choose carefully.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.amber.shade200,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      Text(
                        'Choose your username',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This is how others will find and mention you.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Input ──
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onChanged: _onChanged,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          prefixText: '@',
                          prefixStyle: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          hintText: 'your_username',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: const Color(0xFF1F2533),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white12),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: colorScheme.primary),
                          ),
                          errorText: formatError,
                          errorStyle: const TextStyle(color: Colors.redAccent),
                          suffixIcon: _buildSuffixIcon(availabilityAsync),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Availability status ──
                      if (_debouncedUsername.isNotEmpty && formatError == null)
                        _AvailabilityStatus(async: availabilityAsync),

                      const SizedBox(height: 12),

                      // ── Rules ──
                      _UsernameRules(),

                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _submit,
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
                                  'Continue',
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
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildSuffixIcon(AsyncValue<bool>? async) {
    if (async == null) return null;
    return async.when(
      data: (available) => Icon(
        available ? Icons.check_circle : Icons.cancel,
        color: available ? Colors.greenAccent : Colors.redAccent,
      ),
      loading: () => const SizedBox(
        height: 20,
        width: 20,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => const Icon(Icons.error_outline, color: Colors.orange),
    );
  }
}

class _AvailabilityStatus extends StatelessWidget {
  final AsyncValue<bool>? async;
  const _AvailabilityStatus({required this.async});

  @override
  Widget build(BuildContext context) {
    if (async == null) return const SizedBox.shrink();
    return async!.when(
      data: (available) => Row(
        children: [
          Icon(
            available ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 16,
            color: available ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 6),
          Text(
            available ? 'Username available' : 'Username already taken',
            style: TextStyle(
              color: available ? Colors.greenAccent : Colors.redAccent,
              fontSize: 13,
            ),
          ),
        ],
      ),
      loading: () => const Text(
        'Checking availability...',
        style: TextStyle(color: Colors.white54, fontSize: 13),
      ),
      error: (_, _) => const Text(
        'Could not check availability',
        style: TextStyle(color: Colors.orange, fontSize: 13),
      ),
    );
  }
}

class _UsernameRules extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const rules = [
      '3–20 characters',
      'Lowercase letters, digits, underscore only',
      'Must start with a letter',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rules
          .map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 5, color: Colors.white38),
                  const SizedBox(width: 8),
                  Text(
                    r,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int current;
  final int total;
  const _StepIndicator({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(total, (i) {
        final active = i + 1 == current;
        final done = i + 1 < current;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < total - 1 ? 8 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: done || active ? colorScheme.primary : Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

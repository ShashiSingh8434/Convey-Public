import 'package:convey/shared/widgets/loading_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/providers.dart';
import '../../dashboard/dashboard_page.dart';
import '../../onboarding/pages/profile_setup_page.dart';
import '../../onboarding/pages/username_page.dart';
import '../services/auth_service.dart';
import '../../chats/services/presence_service.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _presenceInitialized = false;

  Future<void> _ensurePresence() async {
    if (_presenceInitialized) return;

    _presenceInitialized = true;

    await PresenceService.instance.initPresence();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const AppLoadingScreen(),
      error: (e, _) => Scaffold(body: Center(child: Text(e.toString()))),
      data: (user) {
        if (user == null) {
          _presenceInitialized = false;
          return const LoginPage();
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensurePresence();
        });

        final userDocAsync = ref.watch(userDocumentProvider);
        return userDocAsync.when(
          loading: () => const AppLoadingScreen(),
          error: (e, _) => Scaffold(body: Center(child: Text(e.toString()))),
          data: (appUser) {
            if (appUser == null) {
              return const AppLoadingScreen();
            }

            if (appUser.username == null || appUser.username!.trim().isEmpty) {
              return const UsernamePage();
            }

            if (!appUser.profileCompleted) {
              return const ProfileSetupPage();
            }

            return const DashboardPage();
          },
        );
      },
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// LOGIN PAGE  (unchanged from previous implementation)
// ─────────────────────────────────────────────────────────────────────────────

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  Future<void> _signIn() async {
    try {
      setState(() => _loading = true);
      await AuthService.instance.signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
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
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 36,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171C28),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 30,
                          offset: Offset(0, 20),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 140,
                              width: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.deepPurple.withValues(
                                      alpha: .35,
                                    ),
                                    blurRadius: 60,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 120,
                              width: 120,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F2533),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Image.asset(
                                'assets/final_zoomed_logo.png',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Welcome to Convey',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Connect. Chat. Collaborate.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'A modern messaging platform built for meaningful '
                          'conversations, real-time communication and seamless '
                          'collaboration.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white60,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 36),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _signIn,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Image.asset(
                                    'assets/google_img.png',
                                    height: 22,
                                  ),
                            label: Text(
                              _loading
                                  ? 'Signing In...'
                                  : 'Continue with Google',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'By continuing, you agree to our Terms of Service '
                          'and Privacy Policy.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                            height: 1.5,
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
      ),
    );
  }
}

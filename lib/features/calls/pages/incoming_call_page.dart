// lib/features/calls/pages/incoming_call_page.dart
//
// Full-screen incoming call page shown when an incoming_call FCM arrives.
// The user can accept or reject the call.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../profile/widgets/profile_avatar.dart';
import '../models/call_model.dart';
import '../models/call_state.dart';
import '../providers/call_providers.dart';

class IncomingCallPage extends ConsumerWidget {
  const IncomingCallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callState = ref.watch(callStateProvider);

    // Auto-dismiss if call ends remotely (caller hung up)
    ref.listen<CallState>(callStateProvider, (_, next) {
      if (!mounted(context)) return;
      if (next.phase == CallPhase.ended || next.phase == CallPhase.idle) {
        context.go('/dashboard');
        ref.read(callStateProvider.notifier).resetCall();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 3),

            // ── Avatar ─────────────────────────────────────────────────────
            ProfileAvatar(
              photoUrl: callState.remotePhotoUrl,
              displayName: callState.remoteName ?? '',
              radius: 60,
            ),

            const SizedBox(height: 24),

            // ── Name ──────────────────────────────────────────────────────
            Text(
              callState.remoteName ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            // ── Type label ────────────────────────────────────────────────
            Text(
              callState.callType == CallType.video
                  ? 'Incoming Video Call'
                  : 'Incoming Call',
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),

            const Spacer(flex: 2),

            // ── Accept / Reject buttons ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject
                _CallActionButton(
                  icon: Icons.call_end_rounded,
                  color: Colors.redAccent,
                  label: 'Decline',
                  onPressed: () async {
                    final callId = callState.callId;
                    final callerUid = callState.remoteUid;
                    if (callId == null || callerUid == null) return;
                    await ref
                        .read(callStateProvider.notifier)
                        .rejectCall(callId: callId, callerUid: callerUid);
                    if (context.mounted) context.go('/dashboard');
                  },
                ),

                // Accept
                _CallActionButton(
                  icon: Icons.call_rounded,
                  color: Colors.greenAccent,
                  label: 'Accept',
                  onPressed: () async {
                    final s = callState;
                    if (s.callId == null || s.remoteUid == null) return;
                    await ref
                        .read(callStateProvider.notifier)
                        .acceptCall(
                          callId: s.callId!,
                          callerUid: s.remoteUid!,
                          callerName: s.remoteName ?? '',
                          callerPhotoUrl: s.remotePhotoUrl,
                          chatId: s.chatId ?? '',
                          callType: s.callType ?? CallType.audio,
                        );
                    if (!context.mounted) return;
                    final route = s.callType == CallType.video
                        ? '/video-call'
                        : '/audio-call';
                    context.go(route);
                  },
                ),
              ],
            ),

            const SizedBox(height: 56),
          ],
        ),
      ),
    );
  }

  bool mounted(BuildContext context) {
    try {
      // ignore: invalid_use_of_protected_member
      context.widget;
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call action button
// ─────────────────────────────────────────────────────────────────────────────

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}

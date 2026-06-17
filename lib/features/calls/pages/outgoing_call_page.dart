// lib/features/calls/pages/outgoing_call_page.dart
//
// Shown to the caller while waiting for the receiver to pick up.
// Reacts to callStateProvider and navigates automatically on state changes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../profile/widgets/profile_avatar.dart';
import '../models/call_model.dart';
import '../models/call_state.dart';
import '../providers/call_providers.dart';

class OutgoingCallPage extends ConsumerStatefulWidget {
  const OutgoingCallPage({super.key});

  @override
  ConsumerState<OutgoingCallPage> createState() => _OutgoingCallPageState();
}

class _OutgoingCallPageState extends ConsumerState<OutgoingCallPage> {
  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);

    ref.listen<CallState>(callStateProvider, (previous, next) {
      if (!mounted) return;

      if (next.phase == CallPhase.active) {
        final route = next.callType == CallType.video
            ? '/video-call'
            : '/audio-call';

        context.pop();
        context.push(route);
        return;
      }

      if (next.phase == CallPhase.ended) {
        context.go('/dashboard');
        ref.read(callStateProvider.notifier).resetCall();
      }
    });

    final statusText = _statusText(callState.callStatus);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111827), Color(0xFF0B0F17)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Avatar Glow
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.08),
                          blurRadius: 30,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ProfileAvatar(
                      photoUrl: callState.remotePhotoUrl,
                      displayName: callState.remoteName ?? '',
                      radius: 72,
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    callState.remoteName ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    callState.callType == CallType.video
                        ? 'Video Call'
                        : 'Audio Call',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: _statusColor(callState.callStatus),
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  const SizedBox(height: 80),

                  _EndCallButton(
                    onPressed: () async {
                      await ref.read(callStateProvider.notifier).endCall();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(CallStatus? status) => switch (status) {
    CallStatus.ringing => 'Ringing...',
    CallStatus.accepted => 'Connecting...',
    CallStatus.connected => 'Connected',
    CallStatus.busy => 'User is busy',
    CallStatus.rejected => 'Call declined',
    CallStatus.ended => 'Call ended',
    CallStatus.timeout => 'No answer',
    _ => 'Calling...',
  };

  Color _statusColor(CallStatus? status) => switch (status) {
    CallStatus.busy ||
    CallStatus.rejected ||
    CallStatus.timeout => Colors.redAccent,
    CallStatus.connected => Colors.greenAccent,
    _ => Colors.white70,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared end-call button widget
// ─────────────────────────────────────────────────────────────────────────────

class _EndCallButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EndCallButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(100),
        child: Ink(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: Colors.redAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.redAccent.withValues(alpha: 0.35),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.call_end_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }
}

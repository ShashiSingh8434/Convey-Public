import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../profile/widgets/profile_avatar.dart';
import '../models/call_state.dart';
import '../providers/call_providers.dart';

class AudioCallPage extends ConsumerStatefulWidget {
  const AudioCallPage({super.key});

  @override
  ConsumerState<AudioCallPage> createState() => _AudioCallPageState();
}

class _AudioCallPageState extends ConsumerState<AudioCallPage> {
  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);

    ref.listen<CallState>(callStateProvider, (previous, next) {
      if (!mounted) return;

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
            const Spacer(),

            ProfileAvatar(
              photoUrl: callState.remotePhotoUrl,
              displayName: callState.remoteName ?? '',
              radius: 70,
            ),

            const SizedBox(height: 24),

            Text(
              callState.remoteName ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              _formatDuration(callState.callDurationSeconds),
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),

            const Spacer(),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlButton(
                  icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                  label: 'Mute',
                  onTap: () {
                    ref.read(callStateProvider.notifier).toggleMute();
                  },
                ),

                _ControlButton(
                  icon: callState.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                  label: 'Speaker',
                  onTap: () {
                    ref.read(callStateProvider.notifier).toggleSpeaker();
                  },
                ),
              ],
            ),

            const SizedBox(height: 36),

            GestureDetector(
              onTap: () {
                ref.read(callStateProvider.notifier).endCall();
                Navigator.of(context).pop();
              },
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;

    return '${mins.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

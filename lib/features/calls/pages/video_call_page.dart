import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../models/call_state.dart';
import '../providers/call_providers.dart';

class VideoCallPage extends ConsumerStatefulWidget {
  const VideoCallPage({super.key});

  @override
  ConsumerState<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends ConsumerState<VideoCallPage> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);

    if (_localRenderer.textureId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_localRenderer.srcObject != callState.localStream) {
      _localRenderer.srcObject = callState.localStream;
    }

    if (_remoteRenderer.srcObject != callState.remoteStream) {
      _remoteRenderer.srcObject = callState.remoteStream;
    }

    ref.listen<CallState>(callStateProvider, (previous, next) {
      if (!mounted) return;

      if (next.phase == CallPhase.ended || next.phase == CallPhase.idle) {
        context.go('/dashboard');
        ref.read(callStateProvider.notifier).resetCall();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: callState.remoteStream != null
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : const Center(child: CircularProgressIndicator()),
          ),

          Positioned(
            top: 60,
            right: 20,
            width: 120,
            height: 180,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: callState.localStream == null
                  ? const ColoredBox(
                      color: Colors.black54,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : RTCVideoView(
                      _localRenderer,
                      mirror: callState.isFrontCamera,
                    ),
            ),
          ),

          Positioned(
            top: 60,
            left: 20,
            child: Text(
              callState.remoteName ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _VideoControlButton(
                  icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                  onTap: () {
                    ref.read(callStateProvider.notifier).toggleMute();
                  },
                ),

                _VideoControlButton(
                  icon: callState.isVideoEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  onTap: () {
                    ref.read(callStateProvider.notifier).toggleVideo();
                  },
                ),

                _VideoControlButton(
                  icon: Icons.cameraswitch,
                  onTap: () {
                    ref.read(callStateProvider.notifier).switchCamera();
                  },
                ),

                GestureDetector(
                  onTap: () {
                    ref.read(callStateProvider.notifier).endCall();
                  },
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _VideoControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

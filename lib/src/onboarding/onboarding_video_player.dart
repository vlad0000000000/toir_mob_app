import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../settings.dart';
import '../utils/go_router_ext.dart';
import 'demo_equipment.dart';

class OnboardingVideoPlayer extends StatefulWidget {
  const OnboardingVideoPlayer({super.key});

  @override
  State<OnboardingVideoPlayer> createState() => _OnboardingVideoPlayerState();
}

class _OnboardingVideoPlayerState extends State<OnboardingVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _completed = false;
  bool _isMuted = false;

  String get _assetPath {
    switch (Settings.onboardingStep) {
      case 1:
        return 'assets/onboarding/1.mp4';
      case 3:
        return 'assets/onboarding/2.mp4';
      case 4:
        return 'assets/onboarding/3.mp4';
      case 5:
        return 'assets/onboarding/4.mp4';
      default:
        return 'assets/onboarding/1.mp4';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(_assetPath)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.play();
        }
      });
    _controller.addListener(_onVideoUpdate);
  }

  void _togglePlayPause() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _controller.removeListener(_onVideoUpdate);
    _controller.pause();

    final step = Settings.onboardingStep;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateAfterVideo(step);
    });
  }

  void _navigateAfterVideo(int step) {
    switch (step) {
      case 1:
        Settings.onboardingStep = 2;
        GoRouter.of(context).clearStackAndNavigate('/actions');
        break;
      case 3:
        GoRouter.of(context).clearStackAndNavigate(
          '/qr_result_demo',
          extra: DemoEquipment.conveyorBelt,
        );
        break;
      case 4:
        Settings.onboardingStep = 5;
        GoRouter.of(context).clearStackAndNavigate('/actions');
        break;
      case 5:
        Settings.onboardingCompleted = true;
        Settings.onboardingInProgress = false;
        Settings.onboardingStep = 6;
        GoRouter.of(context).clearStackAndNavigate('/actions');
        break;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _onVideoUpdate() {
    if (!_controller.value.isInitialized) return;
    if (mounted) setState(() {});
    if (_controller.value.position >= _controller.value.duration &&
        _controller.value.duration > Duration.zero) {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.inverseSurface,
      body: Stack(
        children: [
          if (_isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            )
          else
            Center(
                child: CircularProgressIndicator(color: cs.onInverseSurface)),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: TextButton(
              onPressed: _finish,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.inverseSurface.withValues(alpha: 0.54),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Пропустить',
                  style: TextStyle(color: cs.onInverseSurface, fontSize: 14),
                ),
              ),
            ),
          ),
          if (_isInitialized)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: cs.tertiary,
                      bufferedColor: cs.onInverseSurface.withValues(alpha: 0.24),
                      backgroundColor:
                          cs.onInverseSurface.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _ControlButton(
                        icon: _controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        onTap: _togglePlayPause,
                      ),
                      const SizedBox(width: 8),
                      _ControlButton(
                        icon: _isMuted ? Icons.volume_off : Icons.volume_up,
                        onTap: _toggleMute,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.inverseSurface.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: cs.onInverseSurface, size: 22),
      ),
    );
  }
}

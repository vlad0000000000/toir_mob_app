import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../settings.dart';
import '../utils/go_router_ext.dart';

class OnboardingWelcomeScreen extends StatelessWidget {
  const OnboardingWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/onboarding/lisa.png',
                      width: double.infinity,
                      height: MediaQuery.of(context).size.height * 0.55,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.surface.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded,
                                size: 14, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(
                              'ОБУЧЕНИЕ • 2 МИН',
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '\u{1F44B} Привет, я – Лиза',
                      style: tt.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Помогу вам освоить приложение за пару минут. '
                      'Потренируемся на тестовых данных, чтобы вы уверенно '
                      'начали работу на реальных объектах.',
                      style: tt.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _startOnboarding(context),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Начать обучение'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: TextButton(
                        onPressed: () => _skipOnboarding(context),
                        child: const Text('Пропустить'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startOnboarding(BuildContext context) {
    Settings.onboardingInProgress = true;
    Settings.onboardingStep = 1;
    GoRouter.of(context).clearStackAndNavigate('/onboarding_video');
  }

  void _skipOnboarding(BuildContext context) {
    Settings.onboardingCompleted = true;
    GoRouter.of(context).clearStackAndNavigate('/actions');
  }
}

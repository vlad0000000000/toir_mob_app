import 'package:flutter/material.dart';

class ScannerDemoModal extends StatelessWidget {
  final VoidCallback onStart;

  const ScannerDemoModal({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.qr_code_2_rounded,
                      color: cs.onPrimaryContainer, size: 28),
                ),
                const SizedBox(height: 20),
                Text(
                  'Первый осмотр',
                  style: tt.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Давайте посмотрим, как устроен интерфейс осмотра. '
                  'Это безопасно — мы используем тестовые данные.',
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Начать демо-осмотр'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

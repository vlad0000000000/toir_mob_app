import 'package:flutter/material.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';

/// Полоса «Сессия истекла» над экраном.
///
/// Сервер перестал принимать вход (401). С обычного экрана обходчика сразу
/// выводят на вход, а открытую форму держат ([HoldsSessionSignOut]) — эта
/// полоса объясняет, почему вход откроется, как только он с неё уйдёт.
/// Стоит в `MaterialApp.builder` над всеми экранами: так не нужно
/// встраивать её в каждую форму.
class SessionExpiredStrip extends StatelessWidget {
  const SessionExpiredStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: GlobalState.dataProvider.authExpired,
      builder: (context, expired, _) {
        if (!expired || !GlobalState.isAuthorized) {
          return const SizedBox.shrink();
        }
        return Material(
          color: cs.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMD,
              vertical: AppConstants.spacingSM,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_rounded, size: 20, color: cs.error),
                const SizedBox(width: AppConstants.spacingSM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        SessionStrings.title,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        SessionStrings.formBanner,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onErrorContainer),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

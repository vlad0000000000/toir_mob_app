import 'dart:async';

import 'package:flutter/material.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';

/// Полоса «Нет связи с сервером» над содержимым экрана.
///
/// Пока связи нет, а действие всё равно можно выполнить (ремонт ляжет в
/// очередь), обходчик должен видеть это **до** нажатия кнопки, а не узнавать
/// из снекбара после.
///
/// Пока состояние неизвестно, полосу не рисуем: мигнуть «нет связи» на первом
/// кадре и тут же убрать её — хуже, чем показать на полсекунды позже.
class OfflineBanner extends StatefulWidget {
  /// Что написать под заголовком — у каждого экрана свои последствия офлайна.
  final String? hint;

  const OfflineBanner({super.key, this.hint});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  /// Опрашиваем чуть реже, чем живёт кэш `hasConnectionToServer` (10 секунд),
  /// — так почти каждая проверка бьёт по сети не чаще раза в интервал.
  static const Duration _pollInterval = Duration(seconds: 12);

  bool? _online;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(_pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final online = await GlobalState.hasConnectionToServer;
    if (!mounted || online == _online) return;
    setState(() => _online = online);
  }

  @override
  Widget build(BuildContext context) {
    if (_online != false) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hint = widget.hint;

    // Горизонтальных отступов полоса не задаёт — их даёт список, в который её
    // кладут. А вот отбивку снизу задаёт сама: снаружи её не поставить,
    // потому что видимость полосы известна только здесь, и при связи внизу
    // осталась бы лишняя пустота.
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppConstants.spacingMD),
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: cs.warningContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 20, color: cs.onWarningContainer),
          const SizedBox(width: AppConstants.spacingSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  RepairStrings.noConnection,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onWarningContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hint != null && hint.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: tt.bodySmall?.copyWith(color: cs.onWarningContainer),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

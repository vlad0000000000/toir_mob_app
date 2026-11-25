import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/mobile_support_status.dart';
import '../utils/company_time.dart';

/// Дата окончания поддержки для плашки — в поясе компании, как в карточках
/// сервера для версии 1.0: «dd.MM.yyyy в HH:mm».
String formatSupportEnd(DateTime companyLocal) =>
    DateFormat("dd.MM.yyyy 'в' HH:mm").format(companyLocal);

/// Открывает ссылку RuStore во внешнем приложении (RuStore, без него —
/// браузер). Не вышло — сообщение внизу экрана. Общая для плашки поддержки и
/// объявления о новой версии.
Future<void> openStoreLink(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      const SnackBar(content: Text(MobileSupportStrings.openFailed)),
    );
  }
}

/// Плашка поддержки версии на главной, над кнопками разделов.
///
/// «Скоро завершится» — предупреждающим цветом, «завершена» и «работа
/// ограничена» — цветом ошибки, как полосы отклонённых записей. Кнопка «Обновить в RuStore» — только если
/// сервер прислал ссылку: он даёт её продовой сборке из RuStore, у которой
/// есть более новая. Сама плашка не нажимается — действие одно, на кнопке.
class SupportStatusBanner extends StatelessWidget {
  const SupportStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MobileSupportStatus?>(
      valueListenable: GlobalState.dataProvider.supportStatus,
      builder: (context, saved, _) {
        // Отладочный показ (`PREVIEW_SUPPORT_STATUS`) — вместо настоящего.
        final status = previewSupportStatus(DateTime.now()) ?? saved;
        if (status == null) return const SizedBox.shrink();
        final notice = status.noticeAt(DateTime.now());
        if (notice == SupportNotice.none) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spacingMD),
          child: _Banner(status: status, notice: notice),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  final MobileSupportStatus status;
  final SupportNotice notice;

  const _Banner({required this.status, required this.notice});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final blocked = notice == SupportNotice.workBlocked;
    final obsolete = blocked || notice == SupportNotice.obsolete;
    // Плашка-подсказка приложения: заливка контейнером статуса, без значка
    // (`RemovedEquipmentBanner`). Симметричная (23.11): заголовок и текст по
    // центру, кнопка во всю ширину — действие одно, и оно главное.
    final background = obsolete ? cs.errorContainer : cs.warningContainer;
    final foreground = obsolete ? cs.onErrorContainer : cs.onSurface;
    final uri = status.safeUpdateUri;
    final ends = status.supportEndsAt;
    final body = blocked
        ? MobileSupportStrings.workBlockedBody(uri != null)
        : obsolete
            ? MobileSupportStrings.obsoleteBody(status.versionName, uri != null)
            : MobileSupportStrings.endingSoonBody(
                status.versionName,
                ends == null ? null : formatSupportEnd(CompanyTime.of(ends)),
                uri != null,
              );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMD),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.radiusMD),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            blocked
                ? MobileSupportStrings.workBlockedTitle
                : obsolete
                    ? MobileSupportStrings.obsoleteTitle
                    : MobileSupportStrings.endingSoonTitle,
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXS),
          Text(
            body,
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: foreground),
          ),
          // Действие — FilledButton под текстом, цвет из темы; во всю ширину
          // плашки, значок и подпись по центру кнопки.
          if (uri != null) ...[
            const SizedBox(height: AppConstants.spacingMD),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => openStoreLink(context, uri),
                icon: const Icon(Icons.arrow_circle_up_rounded, size: 20),
                label: const Text(MobileSupportStrings.update),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../strings.dart';
import '../design/app_constants.dart';
import '../design/app_theme.dart';
import '../model/announcement.dart';
import '../utils/company_time.dart';
import '../widgets/support_status_banner.dart';
import 'announcements_service.dart';

/// Дата показа объявления — в поясе компании, как у уведомлений.
String _formatDate(DateTime at) =>
    DateFormat('dd.MM.yyyy HH:mm').format(CompanyTime.of(at));

/// Объявление ещё показывается в [now] — для пилюли «Активно» / «Завершено».
bool isAnnouncementActive(Announcement a, DateTime now) {
  final until = a.visibleUntil;
  return until == null || now.isBefore(until);
}

/// Карточка объявления в списке «Уведомления» — тот же вид, что у
/// уведомления (`NotificationCard`): акцент-полоса слева, подпись типа
/// прописными и точка «не прочитано», заголовок, две строки текста,
/// пилюли, внизу — до какого времени показывается. Нажатие — окно снизу с
/// полным текстом ([showAnnouncementDetail]), оно же отмечает прочитанным.
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;

  const AnnouncementCard({super.key, required this.announcement});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final a = announcement;
    final unread = !a.isRead;
    final accent = !unread
        ? cs.outlineVariant
        : a.isImportant
            ? cs.warning
            : cs.primary;
    final until = a.visibleUntil;

    return Material(
      color: unread ? cs.surface : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        side: BorderSide(
          color: unread
              ? (a.isImportant
                  ? cs.warning.withValues(alpha: 0.4)
                  : cs.outlineVariant)
              : cs.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showAnnouncementDetail(context, a),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.spacingMD,
                    AppConstants.spacingMD - 2,
                    AppConstants.spacingMD,
                    AppConstants.spacingMD - 2,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AnnouncementStrings.typeLabel(a.isRelease)
                                  .toUpperCase(),
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                letterSpacing: 0.6,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.title.isEmpty ? '—' : a.title,
                        style: tt.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight:
                              unread ? FontWeight.w700 : FontWeight.w600,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (a.body.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          a.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppConstants.spacingSM),
                      _AnnouncementPills(announcement: a),
                      if (until != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          AnnouncementStrings.visibleUntil(_formatDate(until)),
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пилюли объявления: состояние показа, «Важное», версия — тем же видом, что
/// пилюли уведомлений (`_StatusPill`, `_PriorityPill`).
class _AnnouncementPills extends StatelessWidget {
  final Announcement announcement;

  const _AnnouncementPills({required this.announcement});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = announcement;
    final active = isAnnouncementActive(a, DateTime.now());
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Pill(
          label: active
              ? AnnouncementStrings.statusActive
              : AnnouncementStrings.statusExpired,
          color: active ? cs.success : cs.onSurfaceVariant,
        ),
        if (a.isImportant)
          _Pill(
            label: AnnouncementStrings.important,
            color: cs.warning,
            icon: Icons.flag_rounded,
          ),
        if (a.isRelease && a.targetVersion != null)
          _Pill(
            label: AnnouncementStrings.version(a.targetVersion!),
            color: cs.info,
            icon: Icons.arrow_circle_up_rounded,
          ),
      ],
    );
  }
}

/// Пилюля — заливка цветом с прозрачностью 0.12, текст и точка (или значок
/// 11px) тем же цветом, радиус `radiusSM`.
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Pill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          SizedBox(width: icon != null ? 4 : 5),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Окно объявления снизу — устроено как подробности уведомления: подпись
/// типа прописными, заголовок, полный текст, пилюли, строки со сроком
/// показа. У объявления о новой версии со ссылкой — кнопка RuStore.
/// Открытие — это и есть прочтение.
Future<void> showAnnouncementDetail(BuildContext context, Announcement a) {
  if (!a.isRead) unawaited(AnnouncementsService.instance.markRead(a.uuid));
  final cs = Theme.of(context).colorScheme;
  final tt = Theme.of(context).textTheme;
  final uri = a.safeUpdateUri;
  final from = a.visibleFrom;
  final until = a.visibleUntil;

  Widget metaRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMD,
            0,
            AppConstants.spacingMD,
            AppConstants.spacingMD,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AnnouncementStrings.typeLabel(a.isRelease).toUpperCase(),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSM),
              Text(
                a.title.isEmpty ? '—' : a.title,
                style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (a.body.isNotEmpty) ...[
                const SizedBox(height: AppConstants.spacingMD),
                Text(a.body, style: tt.bodyMedium),
              ],
              const SizedBox(height: AppConstants.spacingMD),
              _AnnouncementPills(announcement: a),
              const SizedBox(height: AppConstants.spacingMD),
              if (from != null)
                metaRow(
                  Icons.event_available_rounded,
                  AnnouncementStrings.visibleFrom(_formatDate(from)),
                ),
              if (until != null)
                metaRow(
                  Icons.schedule_rounded,
                  AnnouncementStrings.visibleUntil(_formatDate(until)),
                ),
              if (a.isRelease && uri != null) ...[
                const SizedBox(height: AppConstants.spacingLG),
                SizedBox(
                  width: double.infinity,
                  height: AppConstants.buttonHeight,
                  child: ElevatedButton.icon(
                    onPressed: () => openStoreLink(ctx, uri),
                    icon: const Icon(Icons.arrow_circle_up_rounded, size: 20),
                    label: const Text(MobileSupportStrings.update),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

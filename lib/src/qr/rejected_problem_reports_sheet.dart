import 'package:flutter/material.dart';

import '../../global_state.dart';
import '../../strings.dart';
import '../data/problem_report_photos.dart';
import '../design/app_constants.dart';
import '../model/periodic_task_request.dart';
import '../repairs/repair_delete_dialog.dart';

/// Лист разбора отклонённых заявок «Проблема» — по полосе на главной.
///
/// Тот же вид, что у листа отклонённой наработки: запись с оборудованием,
/// комментарием и причиной отказа, действия «Повторить» и «Удалить». Осмотр
/// «Другое» по этим заявкам уже на сервере — не создана только задача для
/// администратора, поэтому удаление не теряет ни комментария, ни фото.
///
/// Перерисовывается по счётчику: фоновый проход может снова отклонить
/// повторённую заявку, пока лист открыт.
class RejectedProblemReportsSheet extends StatelessWidget {
  const RejectedProblemReportsSheet({super.key});

  /// Название оборудования по локальному кэшу: в заявке лежит только uuid.
  static String _equipmentName(String uuid) {
    for (final record in GlobalState.dataProvider.inventoryRecords) {
      if (record.uuid == uuid) return record.name;
    }
    return ProblemReportStrings.unknownEquipment;
  }

  void _closeIfEmpty(BuildContext context) {
    if (GlobalState.dataProvider.rejectedProblemReports.isNotEmpty) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _retry(BuildContext context, PeriodicTaskRequest task) async {
    // Отправку не ждём: очередь подхватит заявку своим проходом, а лист
    // должен закрыться сразу, если разбирать больше нечего.
    await GlobalState.dataProvider.retryRejectedProblemReport(task.key());
    if (context.mounted) _closeIfEmpty(context);
  }

  Future<void> _delete(BuildContext context, PeriodicTaskRequest task) async {
    final confirmed = await confirmRepairDelete(
      context,
      title: ProblemReportStrings.deleteTitle,
      body: ProblemReportStrings.deleteBody(_equipmentName(task.equipmentUuid)),
      note: RepairStrings.deleteIrreversible,
    );
    if (!confirmed || !context.mounted) return;
    await GlobalState.dataProvider.deleteRejectedProblemReport(task.key());
    if (context.mounted) _closeIfEmpty(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ValueListenableBuilder<int>(
      valueListenable: GlobalState.dataProvider.rejectedProblemReportsCount,
      builder: (context, _, __) {
        final items = GlobalState.dataProvider.rejectedProblemReports;
        // Прокрутка — здесь, а не у вызывающего: `Modal` отдаёт листу
        // `Expanded` фиксированной высоты (90% экрана) без прокрутки и
        // отступов. На 320×568 не помещалась уже одна заявка, на 480×1000 —
        // четыре: нижние кнопки уходили за край.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingMD,
            0,
            AppConstants.spacingMD,
            AppConstants.spacingMD,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ProblemReportStrings.sheetTitle,
                textAlign: TextAlign.center,
                style: tt.titleLarge,
              ),
              const SizedBox(height: AppConstants.spacingSM),
              Text(
                ProblemReportStrings.sheetHint,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: AppConstants.spacingMD),
              // Заявок единицы: список строится целиком, без itemBuilder.
              for (final task in items)
                Container(
                  margin: const EdgeInsets.only(bottom: AppConstants.spacingSM),
                  padding: const EdgeInsets.all(AppConstants.spacingMD),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMD),
                    border: Border.all(color: cs.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _equipmentName(task.equipmentUuid),
                        style: tt.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (task.description ?? '').trim().isEmpty
                            ? ProblemReportStrings.noComment
                            : task.description!.trim(),
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppConstants.spacingSM),
                      Text(
                        problemReportStoredReason(task.rejectedReason),
                        style: tt.bodySmall?.copyWith(color: cs.error),
                      ),
                      const SizedBox(height: AppConstants.spacingSM),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _retry(context, task),
                              child: const Text(ProblemReportStrings.retry),
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingSM),
                          Expanded(
                            child: TextButton(
                              onPressed: () => _delete(context, task),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.error,
                              ),
                              child: const Text(ProblemReportStrings.delete),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppConstants.spacingSM),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(ProblemReportStrings.close),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_scan_industry/src/update_manager.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/design/app_constants.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../strings.dart';
import '../../settings.dart';
import '../../src/widgets/square_button.dart' as sq;
import '../widgets/app_bottom_sheet.dart';

class QRActions extends StatefulWidget {
  const QRActions({super.key});

  @override
  State<QRActions> createState() => _QRActionsState();
}

class _QRActionsState extends State<QRActions> {
  bool _showAdditionalButtons = false;

  @override
  void initState() {
    super.initState();
    if (GlobalState.isAuthorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotificationsService.instance.bootstrap();
        // Страховка: после свежей установки логин мог не дотянуть до
        // запуска foreground-сервиса (диалог разрешения, race с навигацией
        // и т. п.). На /actions точно есть стабильный UI — поднимаем
        // сервис, если он не запущен.
        PushNotificationsController.instance.ensureRunning();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        UpdateManager.checkForUpdate(context);
      },
    );

    // Первый массив - первые 3 кнопки (всегда видимы)
    List<Widget> primaryButtons = [
      SquareButton(
        icon: Icons.qr_code_scanner,
        label: Strings.scanner,
        onPressed: () {
          GlobalState.dataProvider.mainSync();
          GoRouter.of(context).clearStackAndNavigate('/qr_scanner');
        },
      ),
      if (GlobalState.dataProvider.company != null &&
          GlobalState.dataProvider.company!.allowRequestsWithoutQr)
        SquareButton(
          icon: Icons.warehouse,
          fontSize: 12,
          label: 'Осмотр оборудования/ТМЦ',
          onPressed: () {
            GlobalState.dataProvider.mainSync();
            GoRouter.of(context).clearStackAndNavigate('/problems');
          },
        ),
      SquareButton(
        icon: Icons.list_alt,
        label: Strings.tasks,
        onPressed: () {
          GlobalState.allowSyncMainOnce = true;
          GoRouter.of(context).clearStackAndNavigate('/tasks');
        },
      ),
      _NotificationsButton(),
    ];

    // Второй массив - остальные кнопки (видимы только если switch включен)
    List<Widget> additionalButtons = [
      SquareButton(
        icon: Icons.sync,
        label: Strings.syncData,
        onPressed: () async {
          final result = await GlobalState.dataProvider.syncDataAndScans();
          switch (result) {
            case SyncResult.noConnection:
              Dialogs.notify(context, "Отсутствует соединение с сервером", "");
            case SyncResult.allSynced:
              Dialogs.notify(context, "Все данные успешно синхронизированы", "");
            case SyncResult.scansSynced:
              Dialogs.notify(context,
                  "Все данные и осмотры успешно синхронизированы", "");
            case SyncResult.scansFailed:
              Dialogs.notify(
                  context, "Не получилось синхронизировать осмотры", "");
          }
        },
      ),
      SquareButton(
        icon: Icons.delete,
        label: "Сбросить осмотры",
        onPressed: () async {
          await GlobalState.dataProvider.scanBox.clear();
          await GlobalState.dataProvider.scanPendingBox.clear();
          Dialogs.notify(context, "Осмотры успешно сброшены", "");
        },
      ),
      SquareButton(
        icon: Icons.info,
        label: "Информация",
        onPressed: () async {
          Dialogs.notifyMD(context, "Осмотры успешно сброшены", "",
              await GlobalState.buildInfo());
        },
      ),
      SquareButton(
        icon: Icons.settings,
        label: "Настройки",
        onPressed: () async {
          showAppModalSheet(
              context,
              child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          bool value = Settings.qrResultShowTasksFirst;
                          bool simplifiedValue = Settings.qrResultShowSimplifiedView;

                          return Column(
                            children: [
                              Text(
                                "Настройки",
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                  child: ListView(
                                shrinkWrap: true,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Показывать задачи сразу после сканирования',
                                            softWrap: true,
                                          ),
                                        ),
                                        Checkbox(
                                          value: value,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            setState(() {
                                              Settings.qrResultShowTasksFirst =
                                                  v;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Упрощенный вид станка на экране результата сканирования',
                                            softWrap: true,
                                          ),
                                        ),
                                        Checkbox(
                                          value: simplifiedValue,
                                          onChanged: (v) {
                                            if (v == null) return;
                                            setState(() {
                                              Settings.qrResultShowSimplifiedView =
                                                  v;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          Settings.resetOnboarding();
                                          GoRouter.of(context)
                                              .clearStackAndNavigate(
                                                  '/onboarding');
                                        },
                                        icon: const Icon(Icons.school),
                                        label: const Text(
                                            'Пройти обучение заново'),
                                      ),
                                    ),
                                  ),
                                ],
                              )),
                              Row(
                                children: [
                                  Expanded(
                                      child: sq.SquareButton(
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                          },
                                          child: Text("Закрыть")))
                                ],
                              )
                            ],
                          );
                        },
                      ),
                    ),
                  ));
        },
      ),
      // SquareButton(
      //   icon: Icons.update,
      //   label: "Обновить приложение",
      //   onPressed: () async {
      //     final updateInfo = await UpdateManager.getUpdateInfo();
      //     if (updateInfo != null) {
      //       await UpdateManager.downloadAndInstall(context, updateInfo);
      //     }
      //   },
      // ),
    ];

    // Объединяем кнопки в зависимости от состояния switch
    List<Widget> allButtons = [
      ...primaryButtons,
      if (_showAdditionalButtons) ...additionalButtons,
    ];

    return Scaffold(
        appBar: MyAppBar.build(context) as AppBar,
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, // Количество столбцов
                    crossAxisSpacing: 16, // Горизонтальный отступ
                    mainAxisSpacing: 16, // Вертикальный отступ
                  ),
                  itemCount: allButtons.length + 1,
                  itemBuilder: (context, index) {
                    if (index < allButtons.length) {
                      return allButtons[index];
                    }

                    return SizedBox(
                      height: 8,
                    );
                  },
                ),
              ),
            ),
            // Switch внизу страницы
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Расширенные настройки',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  SizedBox(width: 12),
                  Switch(
                    value: _showAdditionalButtons,
                    onChanged: (value) {
                      setState(() {
                        _showAdditionalButtons = value;
                      });
                      if (value &&
                          Settings.onboardingInProgress &&
                          Settings.onboardingStep == 5) {
                        GoRouter.of(context)
                            .clearStackAndNavigate('/onboarding_video');
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ));
  }
}

class _NotificationsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NotificationsService.instance.unreadCount,
      builder: (context, count, _) {
        return Stack(
          children: [
            SquareButton(
              icon: Icons.notifications,
              label: 'Уведомления',
              onPressed: () {
                GoRouter.of(context).clearStackAndNavigate('/notifications');
              },
            ),
            if (count > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMD),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onError,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SquareButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double fontSize;

  const SquareButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1, // Гарантирует квадратную форму
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(AppConstants.spacingMD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMD),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 96),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: fontSize),
            )
          ],
        ),
      ),
    );
  }
}

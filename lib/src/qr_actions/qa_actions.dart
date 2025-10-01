import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/app_bar/app_bar.dart';
import 'package:qr_machine_scanner/src/qr/qr_screen.dart';
import 'package:qr_machine_scanner/src/tasks/tasks.dart';
import 'package:qr_machine_scanner/src/utils/dialogs.dart';
import 'package:qr_machine_scanner/src/utils/go_router_ext.dart';
import 'package:qr_machine_scanner/src/widgets/select_task_button.dart';
import 'package:qr_machine_scanner/strings.dart';

class QRActions extends StatelessWidget {
  const QRActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: MyAppBar.build(context) as AppBar,
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Количество столбцов
              crossAxisSpacing: 16, // Горизонтальный отступ
              mainAxisSpacing: 16, // Вертикальный отступ
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              if (index == 0) {
                return SquareButton(
                  icon: Icons.qr_code_scanner,
                  label: Strings.scanner,
                  onPressed: () {
                    GlobalState.needTasksSync = true;
                    GoRouter.of(context).clearStackAndNavigate('/qr_scanner');
                  },
                );
              }
              if (index == 1) {
                return SquareButton(
                  icon: Icons.list_alt,
                  label: Strings.tasks,
                  onPressed: () {
                    GlobalState.needTasksSync = true;
                    GoRouter.of(context).clearStackAndNavigate('/tasks');
                  },
                );
              }
              if (index == 2) {
                return SquareButton(
                  icon: Icons.sync,
                  label: Strings.uploadScans,
                  onPressed: () async {
                    await GlobalState.dataProvider.syncInventory();
                    await GlobalState.dataProvider.syncTypicalProblems();
                    await GlobalState.dataProvider.syncPeriodicityRules();
                    var scans = GlobalState.dataProvider.scanBox.length;
                    if (scans == 0) {
                      Dialogs.notify(
                          context, "Все осмотры уже синхронизированы", "");
                      return;
                    }
                    if (!await GlobalState.hasConnectionToServer) {
                      Dialogs.notify(
                          context, "Отсутствует соединение с сервером", "");
                      return;
                    }
                    await GlobalState.dataProvider.syncScans();
                    scans = GlobalState.dataProvider.scanBox.length;
                    if (scans == 0) {
                      Dialogs.notify(
                          context, "Осмотры успешно синхронизированы", "");
                      return;
                    } else {
                      Dialogs.notify(context,
                          "Не получилось синхронизировать осмотры", "");
                      return;
                    }
                  },
                );
              }
              if (index == 3) {
                return SquareButton(
                  icon: Icons.delete,
                  label: "Сбросить осмотры",
                  onPressed: () async {
                    await GlobalState.dataProvider.scanBox.clear();
                    await GlobalState.dataProvider.scanPendingBox.clear();
                    Dialogs.notify(context, "Осмотры успешно сброшены", "");
                  },
                );
              }
              return SquareButton(
                label: '',
                icon: Icons.add,
                onPressed: () {
                  // Обработка нажатия
                  print('Нажата');
                },
              );
            },
          ),
        ));
  }
}

class SquareButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const SquareButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1, // Гарантирует квадратную форму
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 96,
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            )
          ],
        ),
      ),
    );
  }
}

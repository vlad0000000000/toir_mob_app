import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:qr_scan_industry/settings.dart';
import 'package:qr_scan_industry/src/model/equipment_fault.dart';
import 'package:qr_scan_industry/src/model/responsible_user.dart';
import '../../src/model/company.dart';
import '../../src/model/usage_unit.dart';
import '../../src/model/usage_update.dart';
import '../../src/model/equipment_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../src/login/login_screen.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/periodic_task_models.dart';
import '../../src/model/periodic_task_request.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/pending_repair.dart';
import '../../src/model/pending_repair_update.dart';
import '../../src/model/repair.dart';
import '../../src/model/scan.dart';
import '../../src/model/spare_part.dart';
import '../../src/model/task.dart';
import '../../src/model/typical_problem.dart';
import '../../src/qr/qr_screen.dart';
import '../../src/knowledge_base/knowledge_base_screen.dart';
import '../../src/qr/qa_actions.dart';
import '../../src/qr/qr_result_screen.dart';
import '../../src/notifications/notifications_screen.dart';
import '../../src/notifications/notifications_settings_screen.dart';
import '../../src/notifications/push/notification_router.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../../src/onboarding/onboarding_video_player.dart';
import '../../src/onboarding/onboarding_welcome_screen.dart';
import '../../src/model/consumption_norm.dart';
import '../../src/repairs/create_repair_screen.dart';
import '../../src/repairs/repair_detail_screen.dart';
import '../../src/repairs/repairs_list_screen.dart';
import '../../src/spare_parts/spare_part_detail_screen.dart';
import '../../src/spare_parts/spare_parts_screen.dart';
import '../../src/splash/splash_screen.dart';
import '../../src/style/snack_bar.dart';
import '../../src/app_bar/app_bar.dart';
import '../../src/tasks/tasks.dart';
import '../../src/utils/dependent.dart';
import '../../src/utils/go_router_ext.dart';
import '../../src/widgets/empty_state.dart';

import 'global_state.dart';
import 'src/app_lifecycle/app_lifecycle.dart';
import 'src/data/data_provider.dart';
import 'src/data/hive_storage_location.dart';
import 'src/data/repair_photo_files.dart';
import 'src/design/app_constants.dart';
import 'src/design/app_theme.dart';
import 'src/http/api.dart';
import 'src/model/session.dart';
import 'src/model/user.dart';

/// Открывает бокс-кэш, а если он не читается — пересоздаёт.
///
/// `Hive.openBox` разбирает **все** записи сразу, и одна нечитаемая роняет
/// открытие целиком. Здесь это не просто ошибка: `main()` на этом `await`
/// никогда не завершится, приложение навсегда останется на заставке, и
/// починить это можно только переустановкой — то есть потеряв заодно
/// неотправленные осмотры. Так и вышло, когда в адаптер вложенного
/// `PeriodicTask` дописали поле.
///
/// Годится **только** для боксов, содержимое которых целиком приходит с
/// сервера: потерять их не страшно, следующая синхронизация нальёт заново.
/// Очереди отправки (`scans`, `pending_*`, `repairs` в работе) и данные входа
/// открываются как раньше — молча стереть неотправленное нельзя, такой сбой
/// обязан быть заметным.
Future<Box<T>> _openCacheBox<T>(String name) async {
  try {
    return await Hive.openBox<T>(name);
  } catch (error) {
    debugPrint('[Hive] бокс "$name" не читается ($error) — пересоздаём');
    await Hive.deleteBoxFromDisk(name);
    return await Hive.openBox<T>(name);
  }
}

Future<void> main() async {
  if (kReleaseMode) {
    // Don't log anything below warnings in production.
    Logger.root.level = Level.WARNING;
  }
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: '
        '${record.loggerName}: '
        '${record.message}');
  });
  WidgetsFlutterBinding.ensureInitialized();
  // Push/foreground-service использует dart:isolate и недоступен в Web.
  if (!kIsWeb) {
    FlutterForegroundTask.initCommunicationPort();
    PushNotificationsController.instance.init();
    await PushNotificationRouter.init();
  }
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    /// Prepare the google_mobile_ads plugin so that the first ad loads
    /// faster. This can be done later or with a delay if startup
    /// experience suffers.
  }
  await dotenv.load(fileName: ".env");
  // print(dotenv.env);

  // if (kIsWeb) {
  //   js.context["APP_DESCRIPTION"] = const String.fromEnvironment("APP_DESCRIPTION");
  //   js.context["APP_NAME"] = const String.fromEnvironment("APP_NAME");
  //   // etc..
  //   //Custom DOM event to signal to js the execution of the dart code
  //   html.document.dispatchEvent(html.CustomEvent("dart_loaded"));
  // }

  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    // Путь не зависит от версии приложения: иначе обновление открывало бы
    // пустую базу и теряло неотправленные осмотры. Подробности и перенос
    // данных прошлой версии — в HiveStorageLocation.
    await Hive.initFlutter(await HiveStorageLocation.resolve(packageInfo));
  }

  // await Hive.initFlutter();

  Hive.registerAdapter(UserAdapter());
  Hive.registerAdapter(InventoryAdapter());
  Hive.registerAdapter(ScanAdapter());
  Hive.registerAdapter(SessionAdapter());
  Hive.registerAdapter(TaskAdapter());
  Hive.registerAdapter(TypicalProblemAdapter());
  Hive.registerAdapter(PeriodicityRuleAdapter());
  Hive.registerAdapter(PeriodicTaskAdapter());
  Hive.registerAdapter(PeriodicTaskPhotoAdapter());
  Hive.registerAdapter(LocationAdapter());
  Hive.registerAdapter(EquipmentAdapter());
  Hive.registerAdapter(CustomRoleAdapter());
  Hive.registerAdapter(UsageUnitAdapter());
  Hive.registerAdapter(UsageParameterAdapter());
  Hive.registerAdapter(MaintenanceRoleAdapter());
  Hive.registerAdapter(UsageUpdateAdapter());
  Hive.registerAdapter(CompanyAdapter());
  Hive.registerAdapter(ResponsibleUserAdapter());
  Hive.registerAdapter(EquipmentFaultAdapter());
  Hive.registerAdapter(EquipmentStateAdapter());
  Hive.registerAdapter(PeriodicTaskRequestAdapter());
  Hive.registerAdapter(SparePartAdapter());
  Hive.registerAdapter(RepairAdapter());
  Hive.registerAdapter(RepairConsumptionAdapter());
  Hive.registerAdapter(RepairPhotoAdapter());
  Hive.registerAdapter(RepairNormItemAdapter());
  Hive.registerAdapter(ConsumptionNormAdapter());
  Hive.registerAdapter(PendingRepairAdapter());
  Hive.registerAdapter(PendingRepairUpdateAdapter());

  var dataProvider = DataProvider(
      api: API(),
      userBox: await Hive.openBox<User>('users'),
      inventoryBox: await _openCacheBox<InventoryRecord>('inventory'),
      scanBox: await Hive.openBox<Scan>('scans'),
      scanUsageBox: await Hive.openBox<UsageUpdate>('usage_scans'),
      scanPendingBox: await Hive.openBox<Scan>('pending_scans'),
      scanUsagePendingBox:
          await Hive.openBox<UsageUpdate>('pending_usage_scans'),
      sessionBox: await Hive.openBox<Session>('sessions'),
      usageUnitBox: await _openCacheBox<UsageUnit>('usage_units'),
      typicalProblemBox:
          await _openCacheBox<TypicalProblem>('typical_problems'),
      stringBox: await Hive.openBox<String>('strings'),
      periodicityRuleBox:
          await _openCacheBox<PeriodicityRule>('periodicity_rules'),
      taskBox: await _openCacheBox<Task>('tasks'),
      companyBox: await _openCacheBox<Company>('company'),
      equipmentStateBox:
          await _openCacheBox<EquipmentState>('equipment_states'),
      sparePartBox: await _openCacheBox<SparePart>('spare_parts'),
      repairBox: await _openCacheBox<Repair>('repairs'),
      pendingRepairBox: await Hive.openBox<PendingRepair>('pending_repairs'),
      pendingRepairUpdateBox:
          await Hive.openBox<PendingRepairUpdate>('pending_repair_updates'),
      consumptionNormBox:
          await _openCacheBox<ConsumptionNorm>('consumption_norms'),
      periodicTaskBox:
          await Hive.openBox<PeriodicTaskRequest>('periodic_tasks'),
      periodicTaskPendingBox:
          await Hive.openBox<PeriodicTaskRequest>('pending_periodic_tasks'));

  for (var scan in dataProvider.scanPendingBox.values) {
    await dataProvider.scanPendingBox.delete(scan.key());
    await dataProvider.scanBox.put(scan.key(), scan);
  }

  // Уборка снимков без владельца. Делаем на старте, до того как обходчик
  // успеет снять новый кадр: набор «нужных» путей берётся из очередей, и
  // файл, сохранённый параллельно, в него бы не попал.
  //
  // Осиротеть файл может по-разному: сбой посреди отправки, чистка Hive,
  // переустановка базы. Каталог со снимками переживает всё это, и без уборки
  // они копились бы вечно (п. 4.1.5 отчёта).
  unawaited(RepairPhotoFiles.deleteOrphans(dataProvider.referencedPhotoPaths)
      .then((removed) {
    if (removed > 0)
      debugPrint('[Photos] удалено осиротевших файлов: $removed');
  }));

  GlobalState.dataProvider = dataProvider;
  Settings.dataProvider = dataProvider;

  // Восстанавливаем выбранную тему из Hive (Settings.themeId → AppTheme).
  AppTheme.activeThemeId.value = Settings.themeId;

  // clear Hive of first launch
  // final prefs = await SharedPreferences.getInstance();
  // final isFirstLaunch = prefs.getBool('is_first_launch');
  // if (isFirstLaunch == null || isFirstLaunch) {
  //   // Clear all Hive boxes or specific boxes
  //   await Hive.deleteFromDisk(); // Clears all boxes
  //   // Or: await Hive.box('myBox').clear(); // Clears a specific box
  //   await prefs.setBool('is_first_launch', false);
  // }

  dataProvider.startSyncing();
  dataProvider.startScanSyncing();

  // Отладочная строка внизу экрана обновляется только в отладочной сборке.
  //
  // Внутри `updateDebug` сидит проверка связи, то есть HTTP-запрос к серверу.
  // Раньше цикл крутился всегда — каждые 15 секунд, всё время жизни
  // приложения, включая фон. У обходчика в цеху это лишний трафик и расход
  // батареи ради строки, которой в релизе всё равно не видно.
  if (kDebugMode) {
    Future.sync(() async {
      while (true) {
        await GlobalState.updateDebug();
        await Future.delayed(Duration(seconds: 15));
      }
    });
  }

  runApp(
    MyApp(
      dataProvider: dataProvider,
    ),
  );
}

class MyApp extends StatelessWidget {
  static final _router = GoRouter(
    navigatorKey: PushNotificationRouter.navigatorKey,
    routerNeglect: true,
    redirect: (BuildContext context, GoRouterState state) async {
      final bool isAuthenticated = GlobalState.isAuthorized;

      final bool isGoingToProtectedRoute =
          !state.matchedLocation.startsWith('/login') &&
              state.matchedLocation != '/knowledge_base';

      if (!isAuthenticated && isGoingToProtectedRoute) {
        return '/login';
      }

      if (isAuthenticated && state.matchedLocation == '/login') {
        if (!Settings.onboardingCompleted) {
          return '/onboarding';
        }
        return '/actions';
      }

      // Если приложение было запущено тапом по push-уведомлению — после
      // прохождения авторизационных редиректов перебрасываем сразу на
      // экран уведомлений (один раз).
      if (isAuthenticated && PushNotificationRouter.hasPendingOpen) {
        final target = PushNotificationRouter.pendingLocation;
        if (state.matchedLocation != target) {
          PushNotificationRouter.consumePendingOpen();
          return target;
        }
      }

      return null;
    },
    routes: [
      // Все маршруты отдают NoTransitionPage: анимация смены экранов в
      // приложении отключена целиком. Обходчик листает экраны десятками за
      // обход, и любой переход воспринимается как задержка.
      GoRoute(
        path: '/',
        pageBuilder: (context, state) {
          return const NoTransitionPage<void>(child: SplashScreen());
        },
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          // Без const: конструктор LoginScreen не константный.
          return NoTransitionPage<void>(
            child: LoginScreen(key: const Key('main')),
          );
        },
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) {
          return const NoTransitionPage<void>(
            child: OnboardingWelcomeScreen(key: Key('onboarding')),
          );
        },
      ),
      GoRoute(
        path: '/onboarding_video',
        pageBuilder: (context, state) {
          return const NoTransitionPage<void>(
            child: OnboardingVideoPlayer(key: Key('onboarding_video')),
          );
        },
      ),
      GoRoute(
        path: '/actions',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const QRActions(key: Key('qr_actions')),
          );
        },
      ),
      GoRoute(
        path: '/tasks',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: EquipmentListScreen(
              key: Key('tasks'),
            ),
          );
        },
      ),
      GoRoute(
        path: '/ppr',
        // Как и все остальные маршруты — NoTransitionPage. В ветке ППР здесь
        // был `buildMyTransition` с цветом из `Palette`; и анимация-шторка,
        // и сам `Palette` удалены рефактором (см. остальные 21 маршрут).
        pageBuilder: (context, state) {
          return const NoTransitionPage<void>(
            child: PprListScreen(key: Key('ppr')),
          );
        },
      ),
      GoRoute(
        path: '/problems',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: EquipmentListScreen(
              isProblems: true,
              key: Key('problems'),
            ),
          );
        },
      ),
      GoRoute(
        path: '/repairs',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const RepairsListScreen(key: Key('repairs')),
          );
        },
      ),
      GoRoute(
        path: '/repair_create',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: CreateRepairScreen(
              key: const Key('repair_create'),
              equipment: state.extra as InventoryRecord,
            ),
          );
        },
      ),
      GoRoute(
        path: '/repairs/:uuid',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: RepairDetailScreen(
              key: Key('repair_${state.pathParameters['uuid']}'),
              repairUuid: state.pathParameters['uuid'] ?? '',
              initial: state.extra is Repair ? state.extra as Repair : null,
            ),
          );
        },
      ),
      GoRoute(
        // Карточка локального черновика: та же карточка ремонта, но всё
        // заполненное сохраняется обратно в очередь.
        path: '/repair_draft/:localId',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: RepairDetailScreen(
              key: Key('draft_${state.pathParameters['localId']}'),
              repairUuid: '',
              draftLocalId: state.pathParameters['localId'],
            ),
          );
        },
      ),
      GoRoute(
        path: '/spare_parts',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const SparePartsScreen(key: Key('spare_parts')),
          );
        },
      ),
      GoRoute(
        path: '/spare_parts/:uuid',
        // Без анимации: карточка ЗИП открывается по тапу из списка, и переход
        // «как будто грузится страница» здесь только тормозит — обходчик
        // листает справочник и заглядывает в позиции подряд.
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: SparePartDetailScreen(
              key: Key('spare_part_${state.pathParameters['uuid']}'),
              sparePartUuid: state.pathParameters['uuid'] ?? '',
              initial:
                  state.extra is SparePart ? state.extra as SparePart : null,
            ),
          );
        },
      ),
      GoRoute(
        path: '/knowledge_base',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const KnowledgeBaseScreen(key: Key('knowledge_base')),
          );
        },
      ),
      GoRoute(
        path: '/details/:index',
        pageBuilder: (context, state) {
          // Ни разбор пути, ни поиск оборудования не должны ронять маршрут.
          // Сюда попадают не только из списка: из раздела ППР, по тапу
          // в пуш-уведомлении, из восстановленного стека. Оборудование к
          // этому моменту могло исчезнуть из локального справочника — его
          // удалили на сервере, и синхронизация перезаписала бокс. Раньше
          // `.first` в таком случае бросал `StateError` прямо в build
          // маршрута, и приложение показывало красный экран.
          final index = int.tryParse(state.pathParameters['index'] ?? '');
          final machine = index == null
              ? null
              : GlobalState.dataProvider.equipmentById(index);
          if (machine == null) {
            return const NoTransitionPage<void>(child: _EquipmentGone());
          }
          return NoTransitionPage<void>(
            child: EquipmentDetailScreen(machine: machine),
          );
        },
      ),
      GoRoute(
        path: '/qr_scanner',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const QRScreen(key: Key('qr_scanner')),
            // child: const QRTabsScreen(key: Key('qr_scanner')),
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const NotificationsScreen(key: Key('notifications')),
          );
        },
      ),
      GoRoute(
        path: '/notifications_settings',
        pageBuilder: (context, state) {
          return NoTransitionPage<void>(
            child: const NotificationsSettingsScreen(
                key: Key('notifications_settings')),
          );
        },
      ),
      GoRoute(
        path: '/qr_result',
        pageBuilder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return NoTransitionPage<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result'),
              openDateTime: GlobalState.nowUTCDate,
            ),
          );
        },
      ),
      GoRoute(
        path: '/qr_result_demo',
        pageBuilder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return NoTransitionPage<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result_demo'),
              openDateTime: GlobalState.nowUTCDate,
            ),
          );
        },
      ),
      GoRoute(
        path: '/qr_result_problems',
        pageBuilder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return NoTransitionPage<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result'),
              openDateTime: GlobalState.nowUTCDate,
            ),
          );
        },
      )
    ],
  );

  final DataProvider dataProvider;

  const MyApp({
    super.key,
    required this.dataProvider,
  });

  @override
  Widget build(BuildContext context) {
    // return NestedTabNavigationExampleApp();
    // return MyTabApp();

    return ScreenUtilInit(
      designSize: const Size(750, 1067),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return AppLifecycleObserver(
          child: MultiProvider(
            providers: [
              Provider(
                create: (context) => dataProvider,
              ),
            ],
            child: Builder(builder: (context) {
              var app = ValueListenableBuilder<AppThemeId>(
                valueListenable: AppTheme.activeThemeId,
                builder: (context, _, __) => MaterialApp.router(
                  builder: EasyLoading.init(),
                  title: dotenv.env["APP_TITLE"]!,
                  theme: AppTheme.lightTheme,
                  themeMode: ThemeMode.light,
                  // flutter_localizations здесь намеренно нет: пакет из SDK
                  // требует intl 0.19, а понижение с 0.20 тянет за собой
                  // collection и vector_math до версий, с которыми не
                  // собирается уже сам Flutter. Русские дата и время делаются
                  // своими листами выбора — см. `showSingleDateSheet` и
                  // `showDateRangeSheet` в `widgets/date_range_sheet.dart`,
                  // а также `_TimeWheelSheet` в форме создания ремонта.
                  routeInformationProvider: _router.routeInformationProvider,
                  routeInformationParser: _router.routeInformationParser,
                  routerDelegate: _router.routerDelegate,
                  scaffoldMessengerKey: scaffoldMessengerKey,
                  showPerformanceOverlay: false,
                ),
              );
              return SafeArea(
                child: Column(
                  children: [
                    Expanded(child: app),
                    Builder(builder: (context) {
                      final cs = Theme.of(context).colorScheme;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMD,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.inverseSurface,
                          border: Border(
                            top: BorderSide(
                                color:
                                    cs.onInverseSurface.withValues(alpha: 0.1),
                                width: 0.5),
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Dependent(
                          value: GlobalState.debug,
                          builder: (context, value, widget) {
                            return Text(
                              value,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: cs.onInverseSurface
                                        .withValues(alpha: 0.85),
                                    fontFamily: 'monospace',
                                    height: 1.3,
                                  ),
                              textDirection: TextDirection.ltr,
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Заглушка маршрута `/details/:index`, когда оборудования нет в справочнике.
///
/// Своим экраном, а не редиректом: обходчик пришёл по конкретной ссылке — из
/// раздела ППР, из пуш-уведомления, из восстановленного стека, — и молча
/// переброшенный на другой экран он решил бы, что приложение сломалось.
/// Здесь же прямо сказано, что произошло, и предложено обновить справочник.
class _EquipmentGone extends StatelessWidget {
  const _EquipmentGone();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Оборудование не найдено',
        hint: 'Возможно, его удалили. Синхронизируйте данные и попробуйте '
            'снова.',
        action: ElevatedButton(
          onPressed: () => GoRouter.of(context).backOr('/tasks'),
          child: const Text('К задачам'),
        ),
      ),
    );
  }
}

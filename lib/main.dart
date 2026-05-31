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
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../src/login/login_screen.dart';
import '../../src/model/inventory_record.dart';
import '../../src/model/periodic_task_models.dart';
import '../../src/model/periodic_task_request.dart';
import '../../src/model/periodicity_rule.dart';
import '../../src/model/scan.dart';
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
import '../../src/splash/splash_screen.dart';
import '../../src/style/snack_bar.dart';
import '../../src/tasks/tasks.dart';
import '../../src/utils/dependent.dart';

import 'global_state.dart';
import 'src/app_lifecycle/app_lifecycle.dart';
import 'src/data/data_provider.dart';
import 'src/design/app_theme.dart';
import 'src/http/api.dart';
import 'src/model/session.dart';
import 'src/model/user.dart';
import 'src/style/my_transition.dart';
import 'src/style/palette.dart';

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
  String directory = GlobalState.digest([
    packageInfo.appName,
    packageInfo.packageName,
    packageInfo.version,
    packageInfo.buildNumber
  ].join('|'));
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final appDocumentDir = await getApplicationDocumentsDirectory();
    final customPath =
        '${appDocumentDir.path}/${directory}'; // Define your custom path
    await Hive.initFlutter(customPath);
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

  var dataProvider = DataProvider(
      api: API(),
      userBox: await Hive.openBox<User>('users'),
      inventoryBox: await Hive.openBox<InventoryRecord>('inventory'),
      scanBox: await Hive.openBox<Scan>('scans'),
      scanUsageBox: await Hive.openBox<UsageUpdate>('usage_scans'),
      scanPendingBox: await Hive.openBox<Scan>('pending_scans'),
      scanUsagePendingBox:
          await Hive.openBox<UsageUpdate>('pending_usage_scans'),
      sessionBox: await Hive.openBox<Session>('sessions'),
      usageUnitBox: await Hive.openBox<UsageUnit>('usage_units'),
      typicalProblemBox: await Hive.openBox<TypicalProblem>('typical_problems'),
      stringBox: await Hive.openBox<String>('strings'),
      periodicityRuleBox:
          await Hive.openBox<PeriodicityRule>('periodicity_rules'),
      taskBox: await Hive.openBox<Task>('tasks'),
      companyBox: await Hive.openBox<Company>('company'),
      equipmentStateBox: await Hive.openBox<EquipmentState>('equipment_states'),
      periodicTaskBox: await Hive.openBox<PeriodicTaskRequest>('periodic_tasks'),
      periodicTaskPendingBox: await Hive.openBox<PeriodicTaskRequest>('pending_periodic_tasks'));

  for (var scan in dataProvider.scanPendingBox.values) {
    await dataProvider.scanPendingBox.delete(scan.key());
    await dataProvider.scanBox.put(scan.key(), scan);
  }

  GlobalState.dataProvider = dataProvider;
  Settings.dataProvider = dataProvider;

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

  Future.sync(() async {
    while (true) {
      await GlobalState.updateDebug();
      await Future.delayed(Duration(seconds: 15));
    }
  });

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
      if (isAuthenticated &&
          PushNotificationRouter.hasPendingOpen &&
          state.matchedLocation != '/notifications') {
        PushNotificationRouter.consumePendingOpen();
        return '/notifications';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          return SplashScreen();
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          // const QRScreen(key: Key('main')),
          // return QRResultScreen(GlobalState.dataProvider.machines[0],
          //     key: Key('main'));
          return LoginScreen(key: Key('main'));
        },
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) {
          return const OnboardingWelcomeScreen(key: Key('onboarding'));
        },
      ),
      GoRoute(
        path: '/onboarding_video',
        builder: (context, state) {
          return const OnboardingVideoPlayer(key: Key('onboarding_video'));
        },
      ),
      GoRoute(
        path: '/actions',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: const QRActions(key: Key('qr_actions')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/tasks',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: EquipmentListScreen(
              key: Key('tasks'),
            ),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/problems',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: EquipmentListScreen(
              isProblems: true,
              key: Key('problems'),
            ),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/knowledge_base',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: const KnowledgeBaseScreen(key: Key('knowledge_base')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/details/:index',
        pageBuilder: (context, state) {
          final index = int.parse(state.pathParameters['index']!);
          return buildMyTransition<void>(
            child: EquipmentDetailScreen(
              machine: GlobalState.dataProvider.inventoryRecords
                  .where((element) => element.id == index)
                  .first,
            ),
            // child: const QRTabsScreen(key: Key('qr_scanner')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/qr_scanner',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: const QRScreen(key: Key('qr_scanner')),
            // child: const QRTabsScreen(key: Key('qr_scanner')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: const NotificationsScreen(key: Key('notifications')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/notifications_settings',
        pageBuilder: (context, state) {
          return buildMyTransition<void>(
            child: const NotificationsSettingsScreen(
                key: Key('notifications_settings')),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/qr_result',
        pageBuilder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return buildMyTransition<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result'),
              openDateTime: GlobalState.nowUTCDate,
            ),
            color: context.watch<Palette>().backgroundMain,
          );
        },
      ),
      GoRoute(
        path: '/qr_result_demo',
        builder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return QRResultScreen(
            machine,
            key: const Key('qr_result_demo'),
            openDateTime: GlobalState.nowUTCDate,
          );
        },
      ),
      GoRoute(
        path: '/qr_result_problems',
        pageBuilder: (context, state) {
          final machine = state.extra! as InventoryRecord;
          return buildMyTransition<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result'),
              openDateTime: GlobalState.nowUTCDate,
            ),
            color: context.watch<Palette>().backgroundMain,
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
              Provider(
                create: (context) => Palette(),
              ),
            ],
            child: Builder(builder: (context) {
              var app = MaterialApp.router(
                builder: EasyLoading.init(),
                title: dotenv.env["APP_TITLE"]!,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                routeInformationProvider: _router.routeInformationProvider,
                routeInformationParser: _router.routeInformationParser,
                routerDelegate: _router.routerDelegate,
                scaffoldMessengerKey: scaffoldMessengerKey,
                showPerformanceOverlay: false,
              );
              return SafeArea(
                  child: Column(
                children: [
                  Expanded(child: app),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.black,
                    alignment: Alignment.centerLeft,
                    height: 36,
                    child: Dependent(
                        value: GlobalState.debug,
                        builder: (context, value, widget) {
                          return Text(
                            value,
                            textScaler: TextScaler.linear(0.9),
                            style: TextStyle(color: Colors.white),
                            textDirection: TextDirection.ltr,
                          );
                        }),
                  ),
                ],
              ));
            }),
          ),
        );
      },
    );
  }
}

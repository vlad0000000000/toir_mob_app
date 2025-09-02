import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_machine_scanner/global_state.dart';
import 'package:qr_machine_scanner/src/login/login_screen.dart';
import 'package:qr_machine_scanner/src/model/check.dart';
import 'package:qr_machine_scanner/src/model/machine.dart';
import 'package:qr_machine_scanner/src/model/task.dart';
import 'package:qr_machine_scanner/src/qr/qr_screen.dart';
import 'package:qr_machine_scanner/src/qr_actions/qa_actions.dart';
import 'package:qr_machine_scanner/src/qr_result/qr_result_screen.dart';
import 'package:qr_machine_scanner/src/splash/splash_screen.dart';
import 'package:qr_machine_scanner/src/style/snack_bar.dart';
import 'package:qr_machine_scanner/src/tasks/tasks.dart';
import 'package:qr_machine_scanner/src/utils/dependent.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:themed/themed.dart';

import 'src/app_lifecycle/app_lifecycle.dart';
import 'src/data/data_provider.dart';
import 'src/http/api.dart';
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
  Hive.registerAdapter(MachineAdapter());
  Hive.registerAdapter(MachineCheckAdapter());
  Hive.registerAdapter(TaskAdapter());

  var dataProvider = DataProvider(
      api: API(),
      userBox: await Hive.openBox<User>('users'),
      machineBox: await Hive.openBox<Machine>('machines'),
      machineCheckBox: await Hive.openBox<Check>('machineChecks'),
      taskBox: await Hive.openBox<Task>('tasks'));

  GlobalState.loginBox = await Hive.openBox<User>('login');
  GlobalState.dataProvider = dataProvider;

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
    routerNeglect: true,
    redirect: (BuildContext context, GoRouterState state) async {
      // return '/qr_scanner';
      final bool isAuthenticated = GlobalState.isAuthorized;

      final bool isGoingToProtectedRoute =
          !state.matchedLocation.startsWith('/login');

      if (!isAuthenticated && isGoingToProtectedRoute) {
        return '/login';
      }

      if (isAuthenticated && state.matchedLocation == '/login') {
        return '/actions';
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
        path: '/details/:index',
        pageBuilder: (context, state) {
          final index = int.parse(state.pathParameters['index']!);
          return buildMyTransition<void>(
            child: EquipmentDetailScreen(
              machine: GlobalState.dataProvider.machines
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
        path: '/qr_result',
        pageBuilder: (context, state) {
          final machine = state.extra! as Machine;
          return buildMyTransition<void>(
            child: QRResultScreen(
              machine,
              key: const Key('qr_result'),
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

    final ButtonStyle flatButtonStyle = TextButton.styleFrom(
      foregroundColor: Colors.black87,
      minimumSize: Size(88, 36),
      padding: EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
    );

    final ButtonStyle raisedButtonStyle = ElevatedButton.styleFrom(
      foregroundColor: Colors.black87,
      // backgroundColor: Colors.blue,
      minimumSize: Size(88, 36),
      // elevation: 0,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: const RoundedRectangleBorder(
        // side: BorderSide(width: 3),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    )
        //   .copyWith(backgroundColor: WidgetStateProperty.resolveWith<Color>(
        // (states) {
        //   // return Colors.white.withAlpha(200);
        //   return Colors.yellow.lighter(0.2);
        //   // return Colors.black.lighter(0.9);
        //   // return states.first.
        // },))
        ;
    final ButtonStyle outlineButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.black87,
      minimumSize: Size(88, 36),
      padding: EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
      ),
    ).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) {
          return Colors.red;
        },
      ),
      side: WidgetStateProperty.resolveWith<BorderSide?>(
        (Set<WidgetState> states) {
          if (states.contains(WidgetState.pressed)) {
            return BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1,
            );
          }
          return null;
        },
      ),
    );
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
              final palette = context.watch<Palette>();

              var app = MaterialApp.router(
                builder: EasyLoading.init(),
                title: 'QR Machine Scanner Fedorenko',
                theme: ThemeData.from(
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.blue,
                      contrastLevel: -0.5,
                      secondary: Colors.black,
                      primary: Colors.black),
                  textTheme: TextTheme(
                    bodyMedium: TextStyle(
                      color: palette.textColor,
                    ),
                  ),
                  useMaterial3: true,
                ).copyWith(
                  textButtonTheme:
                      TextButtonThemeData(style: raisedButtonStyle),
                  elevatedButtonTheme:
                      ElevatedButtonThemeData(style: raisedButtonStyle),
                  outlinedButtonTheme:
                      OutlinedButtonThemeData(style: raisedButtonStyle),
                ),
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

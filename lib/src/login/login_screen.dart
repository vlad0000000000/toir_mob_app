import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/widgets/help_link.dart';
import '../../src/model/user.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../settings.dart';
import '../../strings.dart';
import 'package:themed/themed.dart';
import '../../src/exceptions/app_exceptions.dart';

import '../update_manager.dart';

class LoginScreen extends StatefulWidget {
  LoginScreen({super.key});

  @override
  State<StatefulWidget> createState() {
    return _LoginScreenState();
  }
}

class _LoginScreenState extends State<LoginScreen> {
  // final _formKey = GlobalKey<FormState>();
  final TextEditingController loginController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _passwordVisible = false;

  @override
  void initState() {
    _passwordVisible = false;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = context.watch<DataProvider>();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      UpdateManager.checkForUpdate(context);
    },);

    return Scaffold(
      body: Stack(
        children: [
          Form(
            child: Center(
        child: Container(
          width: 0.7.sw,
          height: 1.sh,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 16,
            children: [
              Container(
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(32.0),
                    child: const Image(
                        image: AssetImage('assets/images/icon.png'))),
                width: 0.3.sw,
              ),
              TextFormField(
                controller: loginController,
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: Strings.inputLogin),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return Strings.loginHelp;
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: passwordController,
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(
                          // Based on passwordVisible state choose the icon
                          _passwordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.black.addOpacity(
                              0.5) // Theme.of(context).primaryColorDark
                          ),
                      onPressed: () {
                        // Update the state i.e. toogle the state of passwordVisible variable
                        setState(() {
                          _passwordVisible = !_passwordVisible;
                        });
                      },
                    ),
                    border: const OutlineInputBorder(),
                    labelText: Strings.inputPassword),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return Strings.passwordHelp;
                  }
                  return null;
                },
              ),
              ElevatedButton(
                  onPressed: () async {
                    try {
                      User? currentUser = await dataProvider.login(
                          loginController.text, passwordController.text);

                      if (currentUser != null) {
                        await dataProvider.mainSync();
                        await dataProvider.syncCompany();
                        await GlobalState.updateDebug();
                        NotificationsService.instance.bootstrap();
                        // Ждём `start()`: иначе диалог запроса разрешения на
                        // уведомления (Android 13+) гонится с навигацией и
                        // на свежей установке часто схлопывается до того, как
                        // юзер успеет ответить — сервис в итоге не стартует.
                        await PushNotificationsController.instance.start();
                        if (!Settings.onboardingCompleted) {
                          GoRouter.of(context).clearStackAndNavigate("/onboarding");
                        } else {
                          GoRouter.of(context).clearStackAndNavigate("/actions");
                        }
                        return;
                      }
                    } on WalkerOnlyException {
                      Dialogs.notify(
                          context, Strings.walkerOnlyTitle, Strings.walkerOnlyDesc);
                      return;
                    } on NoConnectionException {
                      Dialogs.notify(
                          context, Strings.noConnectionTitle, Strings.noConnectionDesc);
                      return;
                    } on InvalidCredentialsException {
                      Dialogs.notify(
                          context, Strings.invalidCredentialsTitle, Strings.invalidCredentialsDesc);
                      return;
                    } catch (e) {
                      // Общая ошибка
                      Dialogs.notify(
                          context, Strings.loginFailTitle, Strings.loginFailDesc);
                      return;
                    }

                    // Если дошли сюда, значит что-то пошло не так
                    Dialogs.notify(
                        context, Strings.loginFailTitle, Strings.loginFailDesc);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Text(
                      Strings.login,
                      style: TextStyle(fontSize: 16),
                    ),
                  ))
            ],
          ),
        ),
      )),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: const HelpLink(),
          ),
        ],
      ),
    );
  }
}

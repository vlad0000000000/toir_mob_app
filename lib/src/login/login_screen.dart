import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/widgets/help_link.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../settings.dart';
import '../../strings.dart';
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
  final TextEditingController loginController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;

  @override
  void initState() {
    _passwordVisible = false;
    super.initState();
  }

  @override
  void dispose() {
    loginController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = context.watch<DataProvider>();

    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        UpdateManager.checkForUpdate(context);
      },
    );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Future<void> doLogin() async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        final currentUser = await dataProvider.login(
            loginController.text, passwordController.text);
        if (currentUser != null) {
          await dataProvider.mainSync();
          await dataProvider.syncCompany();
          await GlobalState.updateDebug();
          NotificationsService.instance.bootstrap();
          await PushNotificationsController.instance.start();
          if (!mounted) return;
          if (!Settings.onboardingCompleted) {
            GoRouter.of(context).clearStackAndNavigate("/onboarding");
          } else {
            GoRouter.of(context).clearStackAndNavigate("/actions");
          }
          return;
        }
        if (!mounted) return;
        Dialogs.notify(context, Strings.loginFailTitle, Strings.loginFailDesc);
      } on WalkerOnlyException {
        if (mounted) {
          Dialogs.notify(
              context, Strings.walkerOnlyTitle, Strings.walkerOnlyDesc);
        }
      } on NoConnectionException {
        if (mounted) {
          Dialogs.notify(
              context, Strings.noConnectionTitle, Strings.noConnectionDesc);
        }
      } on InvalidCredentialsException {
        if (mounted) {
          Dialogs.notify(context, Strings.invalidCredentialsTitle,
              Strings.invalidCredentialsDesc);
        }
      } catch (e) {
        if (mounted) {
          Dialogs.notify(
              context, Strings.loginFailTitle, Strings.loginFailDesc);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Form(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(32.0),
                            child: SizedBox(
                              width: 0.3.sw,
                              child: const Image(
                                image: AssetImage('assets/images/icon.png'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Вход в систему',
                          style: tt.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Войдите, чтобы продолжить осмотры',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: loginController,
                          enabled: !_busy,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: InputDecoration(
                            labelText: Strings.inputLogin,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return Strings.loginHelp;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: passwordController,
                          obscureText: !_passwordVisible,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => doLogin(),
                          decoration: InputDecoration(
                            labelText: Strings.inputPassword,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return Strings.passwordHelp;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _busy ? null : doLogin,
                            child: _busy
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: cs.onPrimary,
                                    ),
                                  )
                                : Text(Strings.login),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
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

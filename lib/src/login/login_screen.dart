import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/http/api.dart';
import '../../src/widgets/help_link.dart';
import '../../src/notifications/notifications_service.dart';
import '../../src/notifications/push/push_notifications_controller.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../settings.dart';
import '../../strings.dart';
import '../../src/exceptions/app_exceptions.dart';

import '../update_manager.dart';
import 'subscription_blocked_dialog.dart';

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
    // Сюда вывели принудительно — сервер закрыл доступ компании во время
    // работы. Объясняем почему, иначе выход выглядел бы как сбой.
    //
    // И при открытии экрана, и пока он открыт: блокировка может прийти во
    // время начальной синхронизации входа, когда экран уже на месте и
    // заново не создаётся. Слушаем не саму блокировку, а событие «переход
    // на экран входа выполнен» — окно, показанное раньше перехода, переход
    // закрыл бы вместе со стеком.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingNotice());
    GlobalState.dataProvider.subscriptionNoticeEvents
        .addListener(_onSubscriptionNotice);
  }

  void _onSubscriptionNotice() {
    // После кадра: переход на экран входа только что выполнен.
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPendingNotice());
  }

  /// Показывает причину блокировки, если её ещё не показали, — один раз.
  void _showPendingNotice() {
    final provider = GlobalState.dataProvider;
    final blocked = provider.pendingSubscriptionNotice;
    if (blocked == null || !mounted) return;
    provider.pendingSubscriptionNotice = null;
    _showSubscriptionBlocked(blocked);
  }

  void _showSubscriptionBlocked(SubscriptionBlockedException blocked) {
    showSubscriptionBlockedDialog(context, blocked);
  }

  @override
  void dispose() {
    GlobalState.dataProvider.subscriptionNoticeEvents
        .removeListener(_onSubscriptionNotice);
    loginController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `read`, а не `watch`: DataProvider не ChangeNotifier и положен в дерево
    // обычным Provider, так что подписываться тут не на что — `watch` лишь
    // выглядел реактивным. За изменениями данных следят ревизии кэша
    // (`repairsRevision`, `sparePartsRevision`).
    final dataProvider = context.read<DataProvider>();

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
      // Вход — явное действие обходчика: сеть могла появиться только что, и
      // отвечать ему по памяти об отметке недоступности нельзя.
      API.retryConnectionNow();
      try {
        final currentUser = await dataProvider.login(
            loginController.text, passwordController.text);
        if (currentUser != null) {
          // Та же ли ещё сессия. Во время начальной синхронизации сервер мог
          // закрыть доступ компании — тогда обходчика уже вывели, и
          // продолжать вход (push-сервис, переход на главную) нельзя:
          // запустили бы сервис без пользователя. Причину покажет слушатель
          // блокировки этого же экрана.
          bool sessionAlive() =>
              GlobalState.authUser?.JWTToken == currentUser.JWTToken;
          await dataProvider.mainSync();
          if (!sessionAlive()) return;
          await dataProvider.syncCompany();
          if (!sessionAlive()) return;
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
      } on SubscriptionBlockedException catch (blocked) {
        if (mounted) _showSubscriptionBlocked(blocked);
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

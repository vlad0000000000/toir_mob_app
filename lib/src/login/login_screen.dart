import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../global_state.dart';
import '../../src/data/data_provider.dart';
import '../../src/model/user.dart';
import '../../src/utils/dialogs.dart';
import '../../src/utils/go_router_ext.dart';
import '../../strings.dart';
import 'package:themed/themed.dart';

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
      body: Form(
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
                    User? currentUser = await dataProvider.login(
                        loginController.text, passwordController.text);

                    if (currentUser != null) {
                      GlobalState.authUser = currentUser;
                      await dataProvider.mainSync();
                      await dataProvider.syncCompany();
                      await GlobalState.updateDebug();
                      GoRouter.of(context).clearStackAndNavigate("/actions");
                      return;
                    }

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
    );
  }
}

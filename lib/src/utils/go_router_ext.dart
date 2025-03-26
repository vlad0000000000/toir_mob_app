import 'package:go_router/go_router.dart';

extension GoRouterExtension on GoRouter {
  void clearStackAndNavigate(String location, {Object? extra}) {
    while (canPop()) {
      pop();
    }
    pushReplacement(location, extra: extra);
  }
}

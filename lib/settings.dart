import '../../src/data/data_provider.dart';
import '../../src/design/app_theme.dart';

class Settings {
  static late DataProvider dataProvider;

  /// Активная тема. По умолчанию — fresh (lime green).
  static set themeId(AppThemeId value) {
    dataProvider.stringBox.put('themeId', value.name);
  }

  static AppThemeId get themeId {
    final v = dataProvider.stringBox.get('themeId');
    if (v == null) return AppTheme.defaultThemeId;
    return AppThemeId.values.firstWhere(
      (x) => x.name == v,
      orElse: () => AppTheme.defaultThemeId,
    );
  }

  static set qrResultShowTasksFirst(bool value) {
    dataProvider.stringBox.put('qrResultShowTasksFirst', value ? "1" : "0");
  }

  static bool get qrResultShowTasksFirst {
    var v = dataProvider.stringBox.get('qrResultShowTasksFirst');
    return v != null && v == "1";
  }

  static set qrResultShowSimplifiedView(bool value) {
    dataProvider.stringBox.put('qrResultShowSimplifiedView', value ? "1" : "0");
  }

  static bool get qrResultShowSimplifiedView {
    var v = dataProvider.stringBox.get('qrResultShowSimplifiedView');
    return v != null && v == "1";
  }

  static set notificationsHideRead(bool value) {
    dataProvider.stringBox.put('notificationsHideRead', value ? "1" : "0");
  }

  static bool get notificationsHideRead {
    var v = dataProvider.stringBox.get('notificationsHideRead');
    return v != null && v == "1";
  }

  static set onboardingCompleted(bool value) {
    dataProvider.stringBox.put('onboardingCompleted', value ? "1" : "0");
  }

  static bool get onboardingCompleted {
    var v = dataProvider.stringBox.get('onboardingCompleted');
    return v != null && v == "1";
  }

  static set onboardingInProgress(bool value) {
    dataProvider.stringBox.put('onboardingInProgress', value ? "1" : "0");
  }

  static bool get onboardingInProgress {
    var v = dataProvider.stringBox.get('onboardingInProgress');
    return v != null && v == "1";
  }

  static set onboardingStep(int value) {
    dataProvider.stringBox.put('onboardingStep', value.toString());
  }

  static int get onboardingStep {
    var v = dataProvider.stringBox.get('onboardingStep');
    return v != null ? int.tryParse(v) ?? 0 : 0;
  }

  static void resetOnboarding() {
    onboardingCompleted = false;
    onboardingInProgress = false;
    onboardingStep = 0;
  }
}

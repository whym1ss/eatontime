import 'dart:convert';

import 'package:eat_on_time/data/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates legacy notification days to hours', () async {
    SharedPreferences.setMockInitialValues({
      'user_profile': jsonEncode({
        'id': 'local-test',
        'notificationsEnabled': true,
        'notifyDaysBefore': 5,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final repository = SettingsRepository(prefs);

    final profile = repository.loadProfile('local-test');

    expect(profile.notifyHoursBefore, 120);
    expect(profile.notificationsEnabled, isTrue);
  });

  test('new profiles require explicit notification opt-in', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = SettingsRepository(prefs);

    final profile = repository.loadProfile('local-test');

    expect(profile.notificationsEnabled, isFalse);
    expect(profile.notifyHoursBefore, 72);
  });
}

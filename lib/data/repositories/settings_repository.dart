import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// Локальные настройки и профиль пользователя (SharedPreferences).
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _profileKey = 'user_profile';
  static const _onboardingKey = 'onboarding_done';
  static const _localUserIdKey = 'local_user_id';

  static Future<SettingsRepository> create() async =>
      SettingsRepository(await SharedPreferences.getInstance());

  UserProfile loadProfile(String userId, {String? email}) {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) {
      return UserProfile(id: userId, email: email, createdAt: DateTime.now());
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (!decoded.containsKey('notifyHoursBefore')) {
        final legacyDays = (decoded['notifyDaysBefore'] as num?)?.toInt();
        if (legacyDays != null) decoded['notifyHoursBefore'] = legacyDays * 24;
      }
      final profile = UserProfile.fromJson(decoded);
      return profile.id == userId ? profile : profile.copyWith(id: userId);
    } catch (_) {
      return UserProfile(id: userId, email: email, createdAt: DateTime.now());
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _prefs.setString(_profileKey, jsonEncode(profile.toJson()));
    // Плоские ключи — их читает фоновый изолят workmanager.
    await _prefs.setBool('notifications_enabled', profile.notificationsEnabled);
    await _prefs.setInt('notify_hours_before', profile.notifyHoursBefore);
    await _prefs.setInt('notification_hour', profile.notificationHour);
    await _prefs.setInt('notification_minute', profile.notificationMinute);
    if (!profile.id.startsWith('local-')) {
      await _prefs.setString('supabase_user_id', profile.id);
    } else {
      await _prefs.remove('supabase_user_id');
    }
  }

  bool get onboardingDone => _prefs.getBool(_onboardingKey) ?? false;

  Future<void> setOnboardingDone(bool value) =>
      _prefs.setBool(_onboardingKey, value);

  /// Идентификатор для анонимного (offline) режима.
  Future<String> localUserId() async {
    final existing = _prefs.getString(_localUserIdKey);
    if (existing != null) return existing;
    final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
    await _prefs.setString(_localUserIdKey, id);
    return id;
  }

  Future<void> clear() => _prefs.remove(_profileKey);
}

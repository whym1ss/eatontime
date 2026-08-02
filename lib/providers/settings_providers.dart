import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/storage_zone.dart';
import '../data/models/user_profile.dart';
import 'core_providers.dart';

/// Профиль пользователя с локальным персистом настроек.
class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier(this._ref, UserProfile initial) : super(initial);

  final Ref _ref;

  Future<void> _persist(UserProfile next) async {
    state = next;
    await _ref.read(settingsRepositoryProvider).saveProfile(next);
  }

  Future<void> setNotificationsEnabled(bool value) =>
      _persist(state.copyWith(notificationsEnabled: value));

  Future<void> setNotificationTime(TimeOfDay time) => _persist(
        state.copyWith(
          notificationHour: time.hour,
          notificationMinute: time.minute,
        ),
      );

  Future<void> setNotifyHoursBefore(int hours) =>
      _persist(state.copyWith(notifyHoursBefore: hours));

  Future<void> setThemeMode(String mode) =>
      _persist(state.copyWith(themeMode: mode));

  Future<void> setPremium(bool value) =>
      _persist(state.copyWith(isPremium: value));

  Future<void> setDisplayName(String name) =>
      _persist(state.copyWith(displayName: name));
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);
  final email = ref.watch(supabaseClientProvider)?.auth.currentUser?.email;
  return UserProfileNotifier(ref, repo.loadProfile(userId, email: email));
});

/// Режим темы для MaterialApp.
final themeModeProvider = Provider<ThemeMode>((ref) {
  switch (ref.watch(userProfileProvider).themeMode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

/// Зоны хранения (пока фиксированные, готовы к кастомизации).
final storageZonesProvider = Provider<List<StorageZone>>((ref) {
  return StorageZone.defaults;
});

/// Пройден ли онбординг.
final onboardingDoneProvider = StateProvider<bool>((ref) {
  return ref.watch(settingsRepositoryProvider).onboardingDone;
});

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/local/isar_service.dart';
import '../data/local/product_local_source.dart';
import '../data/remote/product_remote_source.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../services/product_resolution_service.dart';

/// Переопределяется в main() после `IsarService.open()`.
final isarServiceProvider = Provider<IsarService>((ref) {
  throw UnimplementedError(
      'isarServiceProvider должен быть переопределён в main()');
});

/// Переопределяется в main() после `SharedPreferences.getInstance()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider должен быть переопределён в main()');
});

/// Удалось ли поднять Supabase. Если нет — приложение работает чисто офлайн.
final supabaseAvailableProvider = Provider<bool>((ref) => false);

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!ref.watch(supabaseAvailableProvider)) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
});

/// Текущая сессия Supabase (пусто в офлайн-режиме).
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<AuthState?>.empty();
  return client.auth.onAuthStateChange;
});

/// Идентификатор пользователя: из Supabase либо локальный анонимный.
final currentUserIdProvider = Provider<String>((ref) {
  ref.watch(authStateProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final user = ref.watch(supabaseClientProvider)?.auth.currentUser;
  if (user != null) {
    unawaited(prefs.setString('supabase_user_id', user.id));
    return user.id;
  }

  unawaited(prefs.remove('supabase_user_id'));
  final existing = prefs.getString('local_user_id');
  if (existing != null) return existing;

  final id = 'local-${DateTime.now().microsecondsSinceEpoch}';
  unawaited(prefs.setString('local_user_id', id));
  return id;
});

final productLocalSourceProvider = Provider<ProductLocalSource>((ref) {
  return ProductLocalSource(ref.watch(isarServiceProvider).isar);
});

final productRemoteSourceProvider = Provider<ProductRemoteSource?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : ProductRemoteSource(client);
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(
    local: ref.watch(productLocalSourceProvider),
    remote: ref.watch(productRemoteSourceProvider),
    userId: ref.watch(currentUserIdProvider),
  );
});

final productResolutionServiceProvider =
    Provider<ProductResolutionService>((ref) {
  return ProductResolutionService(
    repository: ref.watch(productRepositoryProvider),
    preferences: ref.watch(sharedPreferencesProvider),
    supabase: ref.watch(supabaseClientProvider),
  );
});

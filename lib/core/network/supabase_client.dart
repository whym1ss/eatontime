import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Инициализация Supabase. Ключи передаются через `--dart-define`.
///
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///             --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
class SupabaseBootstrap {
  SupabaseBootstrap._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// Бросает исключение, если ключи не заданы — вызывающий код
  /// должен обработать это и уйти в офлайн-режим.
  static Future<void> initialize() async {
    if (!isConfigured) {
      throw StateError(
        'SUPABASE_URL / SUPABASE_ANON_KEY не заданы — офлайн-режим',
      );
    }
    await Supabase.initialize(
      url: url,
      publishableKey: anonKey,
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
      realtimeClientOptions: const RealtimeClientOptions(
        timeout: Duration(seconds: 15),
      ),
      storageOptions: const StorageClientOptions(retryAttempts: 3),
    );
  }

  /// Создаёт бесшовную анонимную сессию для синхронизации, если в проекте
  /// Supabase разрешены anonymous sign-ins. Ошибка не ломает офлайн-режим.
  static Future<String?> ensureAnonymousSession() async {
    final client = Supabase.instance.client;
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    try {
      final response = await client.auth
          .signInAnonymously()
          .timeout(const Duration(seconds: 4));
      return response.user?.id;
    } catch (_) {
      return null;
    }
  }
}

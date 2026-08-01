import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product.dart';
import '../models/waste_entry.dart';

/// Работа с таблицей `products` в Supabase.
class ProductRemoteSource {
  ProductRemoteSource(this.client);

  final SupabaseClient client;

  static const String table = 'products';
  static const String wasteTable = 'waste_entries';

  /// Все строки пользователя, изменённые позже [since].
  Future<List<Product>> fetchSince(String userId, DateTime? since) async {
    var query = client.from(table).select().eq('user_id', userId);
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }
    final rows = await query.order('updated_at', ascending: false);
    return (rows as List)
        .map((r) => Product.fromSupabase(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> upsertAll(List<Product> products) async {
    if (products.isEmpty) return;
    await client
        .from(table)
        .upsert(products.map((p) => p.toSupabase()).toList());
  }

  Future<void> upsert(Product product) =>
      client.from(table).upsert(product.toSupabase());

  Future<void> deleteById(String id) =>
      client.from(table).delete().eq('id', id);

  Future<void> logWaste(WasteEntry entry) =>
      client.from(wasteTable).insert(entry.toJson()..remove('id'));

  Future<List<WasteEntry>> fetchWaste(String userId, {DateTime? since}) async {
    var query = client.from(wasteTable).select().eq('user_id', userId);
    if (since != null) {
      query = query.gte('wasted_date', since.toUtc().toIso8601String());
    }
    final rows = await query.order('wasted_date', ascending: false);
    return (rows as List)
        .map((r) => WasteEntry.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Поиск в общем каталоге по штрихкоду.
  Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final row = await client
        .from('product_catalog')
        .select()
        .eq('barcode', barcode)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }
}

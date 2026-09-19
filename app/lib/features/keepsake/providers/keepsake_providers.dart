import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/keepsake.dart';

const _kKey = 'keepsakes_v1';

/// Saved walks, newest first. Persisted as JSON in SharedPreferences —
/// plenty for a demo.
class KeepsakesNotifier extends AsyncNotifier<List<Keepsake>> {
  @override
  Future<List<Keepsake>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kKey) ?? const [];
    return raw
        .map((s) => Keepsake.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(Keepsake k) async {
    final current = state.value ?? const <Keepsake>[];
    final next = [k, ...current.where((e) => e.id != k.id)];
    state = AsyncData(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kKey,
      next.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> clearAll() async {
    state = const AsyncData([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }
}

final keepsakesProvider =
    AsyncNotifierProvider<KeepsakesNotifier, List<Keepsake>>(
  KeepsakesNotifier.new,
);

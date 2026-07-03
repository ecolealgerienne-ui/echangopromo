import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/favorites_store.dart';
import '../../../providers/core_providers.dart';

class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController(this._store) : super(_store.getAll());

  final FavoritesStore _store;

  Future<void> toggle(String commercantId) async {
    await _store.toggle(commercantId);
    state = _store.getAll();
  }

  bool isFavorite(String commercantId) => state.contains(commercantId);
}

final favoritesProvider = StateNotifierProvider<FavoritesController, Set<String>>(
  (ref) => FavoritesController(ref.watch(favoritesStoreProvider)),
);

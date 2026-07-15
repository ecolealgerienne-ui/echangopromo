import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/favorites_store.dart';
import '../../../providers/core_providers.dart';

class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController(this._store) : super(_store.getAll());

  final FavoritesStore _store;

  Future<void> toggle(String promoId) async {
    await _store.toggle(promoId);
    state = _store.getAll();
  }

  bool isFavorite(String promoId) => state.contains(promoId);
}

final favoritesProvider = StateNotifierProvider<FavoritesController, Set<String>>(
  (ref) => FavoritesController(ref.watch(favoritesStoreProvider)),
);

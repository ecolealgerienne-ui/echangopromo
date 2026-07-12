import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/local/selected_commune_store.dart';
import '../../../domain/models/commune.dart';
import '../../../providers/core_providers.dart';

final communeListProvider = FutureProvider<List<Commune>>((ref) {
  return ref.watch(communeApiProvider).list();
});

/// Décision produit 2026-07-12 : jusqu'à 4 communes sélectionnables côté
/// client (grandes villes où les communes sont accolées), plafond répété
/// côté backend (`ListPromoQueryDto.communeIds`, `@ArrayMaxSize(4)`).
const kMaxSelectedCommunes = 4;

class SelectedCommunesController extends StateNotifier<List<String>> {
  SelectedCommunesController(this._store) : super(_store.get());

  final SelectedCommuneStore _store;

  Future<void> select(List<String> communeIds) async {
    final capped = communeIds.take(kMaxSelectedCommunes).toList();
    await _store.set(capped);
    state = capped;
  }
}

final selectedCommunesProvider =
    StateNotifierProvider<SelectedCommunesController, List<String>>(
  (ref) => SelectedCommunesController(ref.watch(selectedCommuneStoreProvider)),
);

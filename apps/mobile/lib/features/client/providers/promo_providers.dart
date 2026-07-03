import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/promo.dart';
import '../../../providers/core_providers.dart';
import 'commune_providers.dart';
import 'favorites_provider.dart';

/// Catégorie sélectionnée par le client — recherche guidée par liste
/// fermée, pas de saisie libre (specs §3.1/§5.6). `null` = toutes catégories.
final categoryFilterProvider = StateProvider<Categorie?>((ref) => null);

final promoListProvider = FutureProvider.autoDispose<List<Promo>>((ref) async {
  final communeId = ref.watch(selectedCommuneProvider);
  final categorie = ref.watch(categoryFilterProvider);
  final favorites = ref.watch(favoritesProvider);
  final api = ref.watch(promoApiProvider);

  return api.listActive(
    communeId: communeId,
    categorie: categorie,
    favoriteIds: favorites.toList(),
  );
});

final promoDetailProvider =
    FutureProvider.autoDispose.family<Promo, String>((ref, promoId) {
  return ref.watch(promoApiProvider).detail(promoId);
});

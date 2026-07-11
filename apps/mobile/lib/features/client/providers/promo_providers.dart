import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/promo.dart';
import '../../../providers/core_providers.dart';
import 'commune_providers.dart';
import 'favorites_provider.dart';

/// Catégorie sélectionnée par le client — recherche guidée par liste
/// fermée, pas de saisie libre (specs §3.1/§5.6). `null` = toutes catégories.
final categoryFilterProvider = StateProvider<Categorie?>((ref) => null);

/// Filtre "mes favoris uniquement" — indépendant du tri, feuille "Filtres et
/// tri" (proposition 2026-07-11 : liste plutôt que grille, filtre par
/// favoris/date).
final favoritesOnlyFilterProvider = StateProvider.autoDispose<bool>((ref) => false);

enum PromoSort { expireBientot, plusGrosseReduction, nouveautes }

/// `expireBientot` reproduit le tri par défaut déjà appliqué côté backend
/// (`PromoService.findActiveForClient`) ; les deux autres sont recalculés
/// côté client — volume d'un seul quartier, pas besoin d'un paramètre de tri
/// supplémentaire côté API pour ça.
final promoSortProvider = StateProvider.autoDispose<PromoSort>((ref) => PromoSort.expireBientot);

final promoListProvider = FutureProvider.autoDispose<List<Promo>>((ref) async {
  final communeId = ref.watch(selectedCommuneProvider);
  final categorie = ref.watch(categoryFilterProvider);
  final favorites = ref.watch(favoritesProvider);
  final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
  final sort = ref.watch(promoSortProvider);
  final api = ref.watch(promoApiProvider);

  final promos = await api.listActive(
    communeId: communeId,
    categorie: categorie,
    favoriteIds: favorites.toList(),
  );

  final filtered =
      favoritesOnly ? promos.where((p) => favorites.contains(p.commercantId)).toList() : [...promos];

  switch (sort) {
    case PromoSort.expireBientot:
      filtered.sort((a, b) {
        if (a.dateFin == null || b.dateFin == null) return 0;
        return a.dateFin!.compareTo(b.dateFin!);
      });
    case PromoSort.plusGrosseReduction:
      filtered.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    case PromoSort.nouveautes:
      filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return filtered;
});

final promoDetailProvider =
    FutureProvider.autoDispose.family<Promo, String>((ref, promoId) {
  return ref.watch(promoApiProvider).detail(promoId);
});

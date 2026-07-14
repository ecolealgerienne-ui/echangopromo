import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/promo_api.dart';
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
/// côté client, sur les promos chargées jusqu'ici (pas un tri global
/// serveur) — acceptable tant que le tri par défaut reste celui qui pousse
/// à charger plus de pages.
final promoSortProvider = StateProvider.autoDispose<PromoSort>((ref) => PromoSort.expireBientot);

enum PromoListStatus { loading, loaded, error }

/// État du chargement paginé (retour terrain 2026-07-14 : grosses communes
/// comme Djelfa pouvant dépasser la taille d'une page en promos actives
/// simultanées — bouton "Afficher plus" plutôt qu'une seule page généreuse).
class PromoListState {
  const PromoListState({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.loadingMore = false,
    this.error,
  });

  final PromoListStatus status;
  final List<Promo> items;
  final int total;
  final int page;
  final bool loadingMore;
  final Object? error;

  bool get hasMore => items.length < total;

  PromoListState copyWith({
    PromoListStatus? status,
    List<Promo>? items,
    int? total,
    int? page,
    bool? loadingMore,
    Object? error,
  }) {
    return PromoListState(
      status: status ?? this.status,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error ?? this.error,
    );
  }
}

class PromoListController extends StateNotifier<PromoListState> {
  PromoListController({
    required PromoApi api,
    required List<String> communeIds,
    required Categorie? categorie,
    required List<String> favoriteIds,
  })  : _api = api,
        _communeIds = communeIds,
        _categorie = categorie,
        _favoriteIds = favoriteIds,
        super(const PromoListState(status: PromoListStatus.loading)) {
    _load();
  }

  final PromoApi _api;
  final List<String> _communeIds;
  final Categorie? _categorie;
  final List<String> _favoriteIds;

  Future<void> _load() async {
    state = const PromoListState(status: PromoListStatus.loading);
    try {
      final result = await _fetch(page: 1);
      state = PromoListState(
        status: PromoListStatus.loaded,
        items: result.items,
        total: result.total,
        page: 1,
      );
    } catch (error) {
      state = PromoListState(status: PromoListStatus.error, error: error);
    }
  }

  /// Pull-to-refresh : recharge depuis la page 1 (retour à l'état initial).
  Future<void> refresh() => _load();

  /// Bouton "Afficher plus" — accumule la page suivante à la suite des
  /// promos déjà chargées. Laisse l'erreur remonter à l'appelant (bouton)
  /// pour afficher un SnackBar, sans perdre les promos déjà affichées.
  Future<void> loadMore() async {
    if (state.status != PromoListStatus.loaded || !state.hasMore || state.loadingMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final nextPage = state.page + 1;
      final result = await _fetch(page: nextPage);
      state = state.copyWith(
        items: [...state.items, ...result.items],
        total: result.total,
        page: nextPage,
        loadingMore: false,
      );
    } catch (error) {
      state = state.copyWith(loadingMore: false);
      rethrow;
    }
  }

  Future<PaginatedPromos> _fetch({required int page}) => _api.listActive(
        communeIds: _communeIds,
        categorie: _categorie,
        favoriteIds: _favoriteIds,
        page: page,
      );
}

/// Recréé (donc rechargé depuis la page 1) à chaque changement de commune,
/// catégorie ou favoris — ces trois paramètres influencent la requête
/// serveur elle-même (`favoriteIds` change même le tri backend). `sort` et
/// `favoritesOnlyFilterProvider` restent des filtres purement locaux
/// (`visiblePromosProvider`), appliqués sans redéclencher de requête.
final promoListProvider = StateNotifierProvider.autoDispose<PromoListController, PromoListState>((ref) {
  final api = ref.watch(promoApiProvider);
  final communeIds = ref.watch(selectedCommunesProvider);
  final categorie = ref.watch(categoryFilterProvider);
  final favorites = ref.watch(favoritesProvider);
  return PromoListController(
    api: api,
    communeIds: communeIds,
    categorie: categorie,
    favoriteIds: favorites.toList(),
  );
});

/// Promos affichées à l'écran : filtre favoris + tri appliqués sur les
/// promos chargées jusqu'ici (toutes pages confondues).
final visiblePromosProvider = Provider.autoDispose<List<Promo>>((ref) {
  final state = ref.watch(promoListProvider);
  final favorites = ref.watch(favoritesProvider);
  final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
  final sort = ref.watch(promoSortProvider);

  final filtered =
      favoritesOnly ? state.items.where((p) => favorites.contains(p.id)).toList() : [...state.items];

  switch (sort) {
    case PromoSort.expireBientot:
      filtered.sort((a, b) {
        if (a.dateFin == null || b.dateFin == null) return 0;
        return a.dateFin!.compareTo(b.dateFin!);
      });
    case PromoSort.plusGrosseReduction:
      filtered.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    case PromoSort.nouveautes:
      // publishedAt plutôt que createdAt (2026-07-14) : createdAt peut dater
      // d'un brouillon créé bien avant sa publication, ce qui faussait ce
      // tri. Toutes les promos ici sont déjà publiées (findActiveForClient),
      // publishedAt est donc toujours renseigné — le fallback ne sert qu'à
      // rassurer l'analyseur de types.
      filtered.sort((a, b) =>
          (b.publishedAt ?? b.createdAt).compareTo(a.publishedAt ?? a.createdAt));
  }
  return filtered;
});

final promoDetailProvider =
    FutureProvider.autoDispose.family<Promo, String>((ref, promoId) {
  return ref.watch(promoApiProvider).detail(promoId);
});

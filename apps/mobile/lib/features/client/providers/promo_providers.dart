import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/api/promo_api.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/highlight.dart';
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
final favoritesOnlyFilterProvider =
    StateProvider.autoDispose<bool>((ref) => false);

/// Texte saisi dans la barre de recherche de l'accueil (nom de promo ou de
/// magasin). Envoyé au backend (`search`), pas filtré localement : filtrer
/// côté client ne chercherait que dans les promos déjà chargées.
final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Liste déployée par glissement, sans qu'aucun filtre ne soit actif
/// (demande 2026-07-29). Distinct de la catégorie et de la recherche : le
/// client peut vouloir voir « toutes les promos » en plein écran sans
/// restreindre quoi que ce soit. Les trois états produisent la même
/// disposition, d'où un booléen à part plutôt qu'un détournement des
/// filtres existants.
final listExpandedProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Nombre de promos par rangée dans le fil (demande 2026-08-04). Un seul
/// bouton fait tourner les trois valeurs, dans cet ordre.
enum PromoDensity {
  /// Une par rangée : la ligne détaillée (photo, commerce, prix, badge).
  list(1),

  /// Deux par rangée : carte verticale, photo au-dessus du texte.
  grid(2),

  /// Six par rangée : mosaïque de photos avec la seule remise en incrustation.
  /// À cette largeur (~50 dp sur un téléphone courant) aucun texte n'est
  /// lisible — c'est un mode de survol visuel, pas de lecture.
  mosaic(6);

  const PromoDensity(this.columns);

  /// Nombre de colonnes de la grille. `list` vaut 1 mais reste une `ListView`
  /// : la ligne détaillée n'a pas de hauteur fixe, une grille l'obligerait à
  /// un ratio unique alors que le badge « expire bientôt » la fait varier.
  final int columns;

  /// Valeur suivante dans le cycle, en boucle.
  PromoDensity get next =>
      PromoDensity.values[(index + 1) % PromoDensity.values.length];
}

/// Préférence d'affichage, pas un filtre : volontairement absente de
/// `_resetToHome` (promo_list_screen.dart), qui ne remet à zéro que ce qui
/// restreint les résultats. Sans `autoDispose`, pour survivre à un aller-
/// retour vers la carte ou la fiche d'une promo.
final promoDensityProvider =
    StateProvider<PromoDensity>((ref) => PromoDensity.list);

enum PromoSort { expireBientot, plusGrosseReduction, nouveautes }

/// `nouveautes` reproduit le tri par défaut déjà appliqué côté backend
/// (`PromoService.findActiveForClient`, retour terrain 2026-07-14 : les
/// plus récemment publiées en premier) ; les deux autres sont recalculés
/// côté client, sur les promos chargées jusqu'ici (pas un tri global
/// serveur) — acceptable tant que le tri par défaut reste celui qui pousse
/// à charger plus de pages.
final promoSortProvider =
    StateProvider.autoDispose<PromoSort>((ref) => PromoSort.nouveautes);

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
    required String search,
  })  : _api = api,
        _communeIds = communeIds,
        _categorie = categorie,
        _favoriteIds = favoriteIds,
        _search = search,
        super(const PromoListState(status: PromoListStatus.loading)) {
    _load();
  }

  final PromoApi _api;
  final List<String> _communeIds;
  final Categorie? _categorie;
  final List<String> _favoriteIds;
  final String _search;

  Future<void> _load() async {
    // ⚠️ Aucune commune choisie ⇒ on ne demande rien. Le serveur traite
    // `communeIds: []` comme **aucun filtre** et non comme « aucune commune »
    // (`if (query.communeIds?.length)`, `PromoService.findActiveForClient`) :
    // il renverrait une page entière de promos de toutes les communes, que
    // l'écran n'affichera jamais puisqu'il montre `_NoCommuneSelected` à la
    // place. La requête ne coûtait donc rien d'autre que son coût
    // (2026-08-05).
    //
    // L'état reste `loaded` avec zéro promo : c'est l'écran, et lui seul, qui
    // distingue « pas configuré » de « rien à voir » — l'état de chargement
    // n'a pas à porter cette différence, il ne saurait pas la rendre.
    if (_communeIds.isEmpty) {
      state = const PromoListState(status: PromoListStatus.loaded);
      return;
    }
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
    if (state.status != PromoListStatus.loaded ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
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
        search: _search,
        page: page,
      );
}

/// Recréé (donc rechargé depuis la page 1) à chaque changement de commune,
/// catégorie ou favoris — ces trois paramètres influencent la requête
/// serveur elle-même (`favoriteIds` change même le tri backend). `sort` et
/// `favoritesOnlyFilterProvider` restent des filtres purement locaux
/// (`visiblePromosProvider`), appliqués sans redéclencher de requête.
final promoListProvider =
    StateNotifierProvider.autoDispose<PromoListController, PromoListState>(
        (ref) {
  final api = ref.watch(promoApiProvider);
  final communeIds = ref.watch(selectedCommunesProvider);
  final categorie = ref.watch(categoryFilterProvider);
  final favorites = ref.watch(favoritesProvider);
  final search = ref.watch(searchQueryProvider);
  return PromoListController(
    api: api,
    communeIds: communeIds,
    categorie: categorie,
    favoriteIds: favorites.toList(),
    search: search,
  );
});

/// Promos affichées à l'écran : filtre favoris + tri appliqués sur les
/// promos chargées jusqu'ici (toutes pages confondues).
final visiblePromosProvider = Provider.autoDispose<List<Promo>>((ref) {
  final state = ref.watch(promoListProvider);
  final favorites = ref.watch(favoritesProvider);
  final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
  final sort = ref.watch(promoSortProvider);

  final search = ref.watch(searchQueryProvider).trim().toLowerCase();

  var filtered = favoritesOnly
      ? state.items.where((p) => favorites.contains(p.id)).toList()
      : [...state.items];

  // Le backend filtre déjà via `search`, mais on refiltre ici. Deux raisons :
  // le résultat est immédiat pendant que la requête part (pas d'attente de
  // l'aller-retour), et surtout la liste reste juste même si le serveur
  // ignore le paramètre — c'est exactement ce qui s'est produit avec un
  // backend pas encore déployé : `ValidationPipe({whitelist: true})` retire
  // silencieusement tout paramètre qu'il ne connaît pas, et la recherche
  // renvoyait alors la totalité des promos.
  if (search.isNotEmpty) {
    final terms = search.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    filtered = filtered.where((promo) {
      final haystack =
          '${promo.description} ${promo.commercantNom ?? ''}'.toLowerCase();
      // Tous les mots doivent apparaître, dans n'importe quel ordre :
      // « brosse dents » trouve « brosse à dents » sans exiger la formulation
      // exacte, mais « brosse » seul ne remonte plus tout le catalogue.
      return terms.every(haystack.contains);
    }).toList();
  }

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
      filtered.sort((a, b) => (b.publishedAt ?? b.createdAt)
          .compareTo(a.publishedAt ?? a.createdAt));
  }
  return filtered;
});

final promoDetailProvider =
    FutureProvider.autoDispose.family<Promo, String>((ref, promoId) {
  return ref.watch(promoApiProvider).detail(promoId);
});

/// Bandeau "Top promos" de l'accueil.
///
/// Depuis 2026-07-30 il est **curé par l'admin** (`GET /highlight`) : c'est
/// lui qui choisit les diapositives, leur ordre, et peut y importer une
/// image dédiée. Sans curation active exploitable, le backend retombe de
/// lui-même sur le classement calculé d'avant (les plus fortes réductions,
/// `sort=discount`) — l'app n'a donc qu'un seul appel et le bandeau ne se
/// vide jamais faute de configuration.
///
/// Volontairement indépendant de `promoListProvider` : ce bandeau ne suit ni
/// la recherche ni la catégorie, il reste une vitrine stable. La commune
/// n'est transmise que pour le repli calculé, une sélection éditoriale étant
/// globale par nature.
final topPromosProvider = FutureProvider.autoDispose<List<Highlight>>((ref) {
  final communeIds = ref.watch(selectedCommunesProvider);
  return ref.watch(highlightApiProvider).list(communeIds: communeIds);
});

/// "Autres promos du magasin" sur la fiche promo. La promo consultée est
/// retirée de la liste côté client : le backend n'a pas à connaître le
/// contexte d'affichage pour ça.
final shopPromosProvider = FutureProvider.autoDispose
    .family<List<Promo>, ({String commercantId, String excludePromoId})>(
        (ref, args) async {
  final result = await ref.watch(promoApiProvider).listActive(
        commercantId: args.commercantId,
        limit: 10,
      );
  return result.items
      .where((promo) => promo.id != args.excludePromoId)
      .toList();
});

/// Fiche publique du commerçant. Partagée entre la fiche promo et tout écran
/// qui a besoin du téléphone ou de la position — évite qu'un second écran
/// redéclare le même appel dans son propre fichier (règle d'audit #21).
final commercantPublicProfileProvider =
    FutureProvider.autoDispose.family<Commercant, String>((ref, commercantId) {
  return ref.watch(commercantApiProvider).publicProfile(commercantId);
});

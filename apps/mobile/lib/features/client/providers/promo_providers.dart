import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../data/api/promo_api.dart';
import '../../../domain/enums/categorie.dart';
import '../../../domain/models/commercant.dart';
import '../../../domain/models/highlight.dart';
import '../../../domain/models/promo.dart';
import '../../../providers/core_providers.dart';
import 'favorites_provider.dart';
import 'location_providers.dart';
import 'position_providers.dart';

/// Catégorie sélectionnée par le client — recherche guidée par liste
/// fermée, pas de saisie libre (specs §3.1/§5.6). `null` = toutes catégories.
final categoryFilterProvider = StateProvider<Categorie?>((ref) => null);

/// **Le client est-il DANS ses favoris ?** — une destination, pas un filtre.
///
/// ⚠️ **Ce provider s'appelait `favoritesOnlyFilterProvider` jusqu'au
/// 2026-08-16, et le nom disait la vérité : c'était un filtre.** Il était
/// piloté par deux contrôles qui ne racontaient pas la même chose — un
/// interrupteur dans la feuille « Filtres et tri », et l'onglet « Favoris » de
/// la barre du bas. La barre l'affichait comme un **lieu** (`selectedIndex`),
/// la pastille de l'en-tête comme un **filtre actif** : les deux affirmations
/// à l'écran en même temps.
///
/// Le sens retenu est le **lieu**, parce que c'est ce qu'une barre d'onglets
/// veut dire partout ailleurs et qu'on ne rééduque pas ce réflexe. Quatre
/// conséquences, toutes visibles à l'usage :
///
/// - y entrer efface catégorie et recherche (`_enterFavorites`), comme
///   « Accueil » le fait déjà. Sans ça, un client ayant 12 cœurs et une
///   catégorie active en voyait **2**, et rien à l'écran ne disait pourquoi ;
/// - on en sort par « Accueil », pas en retapant l'onglet — un onglet qui
///   bascule n'est pas un onglet ;
/// - l'interrupteur a quitté la feuille, qui ne porte plus qu'un tri ;
/// - la pastille « filtres actifs » ne le compte plus, sinon elle continuerait
///   de contredire l'onglet.
///
/// ⚠️ **La carte a son PROPRE provider** (`mapFavoritesOnlyProvider`), et ce
/// n'est pas une mise en commun oubliée : là-bas le cœur est un vrai filtre —
/// il ne remet rien à zéro et ne désigne aucune destination. Deux natures
/// derrière le même mot. Le filtre catégorie, lui, est un filtre des deux
/// côtés : c'est précisément pour ça qu'il est partagé, et le raisonnement ne
/// se transpose pas.
final favoritesModeProvider = StateProvider.autoDispose<bool>((ref) => false);

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

enum PromoSort { proximite, expireBientot, plusGrosseReduction, nouveautes }

/// ⚠️ **Le défaut était `nouveautes`, et il annulait le tri du serveur.**
///
/// Le commentaire qui vivait ici affirmait que `nouveautes` « reproduit le tri
/// par défaut déjà appliqué côté backend ». C'était exact jusqu'à la bascule
/// géographique : depuis, `findActiveForClient` ordonne **par distance**
/// croissante dès qu'une position est en jeu, et le re-tri local écrasait donc
/// systématiquement cet ordre — la phrase est restée juste d'apparence pendant
/// que le fait qu'elle décrivait avait changé de camp (règle #30 : un
/// commentaire ne peut pas échouer).
///
/// Ce que ça donnait, mesuré le 2026-08-14 sur le décor, `search=promo` : le
/// serveur rendait 65 résultats de 0,1 km à 245 km, **strictement ordonnés par
/// distance** ; l'app affichait en 5ᵉ position une promo à **231,7 km**, devant
/// des dizaines à 100 mètres. C'est ce que le tri par recherche « globale »
/// laissait voir, et c'est ce que `proximite` referme : le proche d'abord est
/// de nouveau vrai **à l'écran**, pas seulement dans la réponse serveur.
///
/// ⚠️ La phrase qui suivait ici — « la recherche reste volontairement sans
/// rayon » — a été vraie une demi-journée. La décision a été inversée le même
/// 2026-08-14 : la recherche respecte désormais le cadre, et le cadre est
/// plafonné par le maximum du serveur (`rayonBorne`). Un commentaire qui survit
/// à la décision qu'il décrit est précisément ce que la règle 30 vise.
final promoSortProvider =
    StateProvider.autoDispose<PromoSort>((ref) => PromoSort.proximite);

/// Réordonne [promos] **sur place**, du plus proche de [repere] au plus loin.
///
/// ⚠️ `repere` absent : on ne touche à rien. L'ordre reçu du serveur est déjà
/// par distance croissante autour du point de recherche — le remplacer par un
/// tri calculé depuis un point inventé serait pire que ne rien faire (règle 29).
///
/// ⚠️ Une promo sans coordonnées part à la **fin**, jamais en tête. La traiter
/// comme « distance 0 » — ce que ferait le moindre `?? 0` — la placerait devant
/// le commerce d'à côté, et c'est exactement le genre de valeur de repli qui
/// rend un écran faux sans rien signaler.
void trierParProximite(List<Promo> promos, LatLng? repere) {
  if (repere == null) return;
  double? ecart(Promo p) =>
      distanceTo(repere, p.commercantLatitude, p.commercantLongitude);
  promos.sort((a, b) {
    final da = ecart(a);
    final db = ecart(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
}

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
    required (double, double)? point,
    required double? radiusKm,
    required Categorie? categorie,
    required List<String> favoriteIds,
    required String search,
    required bool favoritesOnly,
  })  : _api = api,
        _favoritesOnly = favoritesOnly,
        _point = point,
        _radiusKm = radiusKm,
        _categorie = categorie,
        _favoriteIds = favoriteIds,
        _search = search,
        super(const PromoListState(status: PromoListStatus.loading)) {
    _load();
  }

  final PromoApi _api;

  /// `null` = le client n'a rien enregistré, donc **on ne transmet rien** et le
  /// serveur applique son propre point par défaut.
  ///
  /// ⚠️ Contrairement au cas des communes, on **interroge quand même** : le
  /// serveur sait quoi répondre sans position (§5.6 du plan), et une liste
  /// vide serait ici un mensonge — il y a bien des promos à montrer, autour du
  /// point par défaut. C'est l'inverse exact de l'ancien comportement, où
  /// `communeIds: []` valait « aucun filtre » et rendait tout le pays.
  final (double, double)? _point;
  final double? _radiusKm;
  final Categorie? _categorie;
  final List<String> _favoriteIds;
  final String _search;

  /// ⚠️ Envoyé au serveur, pas seulement appliqué à l'écran : le filtre local
  /// ne voyait que les pages déjà chargées, si bien qu'un favori hors du rayon
  /// disparaissait de l'onglet sans un mot (R7).
  final bool _favoritesOnly;

  Future<void> _load() async {
    state = const PromoListState(status: PromoListStatus.loading);
    try {
      final result = await _fetch(page: 1);
      // ⚠️ **`mounted` après CHAQUE `await`.** Quitter l'accueil pendant qu'une
      // requête est en vol détruit ce contrôleur ; la réponse arrive ensuite et
      // `state = …` lève « Tried to use PromoListController after dispose was
      // called ». Trouvé le 2026-08-05 par le parcours de signalement, qui
      // ouvre une fiche juste après avoir tapé une recherche.
      if (!mounted) return;
      state = PromoListState(
        status: PromoListStatus.loaded,
        items: result.items,
        total: result.total,
        page: 1,
      );
    } catch (error) {
      if (!mounted) return;
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
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        total: result.total,
        page: nextPage,
        loadingMore: false,
      );
    } catch (error) {
      // Même garde : sans elle, une erreur réseau survenant après un départ
      // d'écran lèverait à son tour, en masquant l'erreur d'origine.
      if (!mounted) return;
      state = state.copyWith(loadingMore: false);
      rethrow;
    }
  }

  Future<PaginatedPromos> _fetch({required int page}) => _api.listActive(
        point: _point,
        radiusKm: _radiusKm,
        categorie: _categorie,
        favoriteIds: _favoriteIds,
        favoritesOnly: _favoritesOnly,
        search: _search,
        page: page,
      );
}

/// Recréé (donc rechargé depuis la page 1) à chaque changement de point,
/// catégorie ou favoris — ces trois paramètres influencent la requête
/// serveur elle-même (`favoriteIds` change même le tri backend). `sort` et
/// `favoritesModeProvider` s'appliquent en plus **localement**
/// (`visiblePromosProvider`), sans redéclencher de requête.
///
/// ⚠️ **C'est ici que passe la porte de consentement**, et à un seul endroit :
/// `clientPositionProvider` rend `null` tant que le client n'a rien enregistré,
/// et `point: null` fait que la requête ne porte **aucune coordonnée**. Le
/// serveur applique alors son propre défaut. Reproduire cette règle dans chaque
/// écran appelant, c'est celui qu'on oublie qui transmettra (règle #30).
///
/// ⚠️ Le rayon n'est envoyé qu'avec un point, et il ne vient **jamais** d'une
/// constante recopiée ici (règle #32) : soit du cadrage que le client a posé en
/// zoomant, soit, à défaut, de la configuration serveur.
///
/// ⚠️ **L'ordre des deux compte.** Prendre le défaut serveur en premier — ce que
/// faisait ce provider jusqu'au 2026-08-14 — jetait le zoom : depuis Alger,
/// cadrer un quartier puis revenir à la liste montrait tout Alger. Le point
/// était juste, la largeur non, et rien à l'écran ne distinguait les deux.
final promoListProvider =
    StateNotifierProvider.autoDispose<PromoListController, PromoListState>(
        (ref) {
  final api = ref.watch(promoApiProvider);
  final point = ref.watch(clientPositionProvider);
  final config = ref.watch(clientGeoConfigProvider).valueOrNull;
  // Le cadrage du client, borné par ce que le SERVEUR accepte au plus, et à
  // défaut le rayon qu'il applique lui-même. Les deux viennent de
  // `GET /promo/config` : aucun chiffre n'est écrit ici (règle 32).
  final rayonKm = rayonBorne(point?.rayonKm, config?.maxRadiusKm) ??
      config?.defaultRadiusKm;
  final categorie = ref.watch(categoryFilterProvider);
  final favorites = ref.watch(favoritesProvider);
  final search = ref.watch(searchQueryProvider);
  final favoritesOnly = ref.watch(favoritesModeProvider);
  return PromoListController(
    api: api,
    point: point?.coordonnees,
    favoritesOnly: favoritesOnly,
    radiusKm: rayonKm,
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
  final favoritesOnly = ref.watch(favoritesModeProvider);
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
    case PromoSort.proximite:
      // ⚠️ **Trier ici plutôt que se contenter de l'ordre serveur**, alors que
      // celui-ci est déjà par distance croissante. Trois raisons, et chacune
      // suffirait :
      //
      // 1. l'onglet Favoris et « autres promos du magasin » sont des périmètres
      //    explicites : le serveur n'y applique **aucun** ordre géographique
      //    (`perimetreExplicite`). Sans ce tri local, le libellé mentirait
      //    exactement là ;
      // 2. le serveur ordonne depuis le point de RECHERCHE ; l'écran affiche
      //    des distances depuis le point de RÉFÉRENCE (le GPS quand il est là).
      //    Deux ordres différents affichés côte à côte donneraient une liste où
      //    les distances ne sont pas croissantes — visible, et incompréhensible ;
      // 3. le tri porte sur les pages déjà chargées, comme les deux autres.
      //
      // Repère absent (config pas encore répondu, pas de GPS, rien
      // d'enregistré) : on ne touche à rien et l'ordre du serveur reste. Un
      // tri fabriqué depuis un point inventé serait pire que pas de tri
      // (règle 29).
      trierParProximite(filtered, ref.watch(pointDeReferenceProvider));
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
  final point = ref.watch(clientPositionProvider);
  // Même cadrage que la liste : deux géographies différentes sur le même écran
  // donneraient un bandeau « autour de vous » qui ne parle pas du même « vous »
  // que la liste juste en dessous.
  final config = ref.watch(clientGeoConfigProvider).valueOrNull;
  final rayonKm = rayonBorne(point?.rayonKm, config?.maxRadiusKm) ??
      config?.defaultRadiusKm;
  return ref
      .watch(highlightApiProvider)
      .list(point: point?.coordonnees, radiusKm: rayonKm);
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

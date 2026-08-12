import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/map_shop.dart';
import '../../domain/models/client_geo_config.dart';
import '../../domain/models/promo.dart';

/// Le backend pagine `/promo` et `/promo/me/all` (`{items, total, page,
/// limit}`). `listMine()` reste une page unique généreuse — pour l'**aperçu**
/// des promos, qui tolère d'être tronqué.
///
/// ⚠️ Sa justification d'origine (« plafond métier de 5 promos actives, jamais
/// approché ») était fausse : le plafond porte sur 5 **publiées**, cet endpoint
/// renvoie tous les statuts, et un commerçant actif dépasse 100 promos cumulées
/// en quelques mois. Le décompte d'emplacements ne se dérive donc plus d'ici —
/// il vient de [PromoApi.fetchSlots] (revue 2026-08-05).
const _pageSize = 100;

/// `listActive()` pagine réellement côté mobile via bouton "Afficher plus"
/// (retour terrain 2026-07-14 : grosses communes type Djelfa dépassant cette
/// taille en promos actives simultanées).
const _activePageSize = 50;

/// Occupation du plafond de promos actives, telle que le serveur la compte.
///
/// `plafond` vient du serveur lui aussi : l'app recopiait `5` dans
/// `kMaxPromosActives`, une règle métier qui vit dans `PromoService`
/// (`MAX_PROMOS_ACTIVES`) — règle #32.
class PromoSlots {
  const PromoSlots({required this.enLigne, required this.plafond});

  factory PromoSlots.fromJson(Map<String, dynamic> json) => PromoSlots(
        enLigne: json['enLigne'] as int,
        plafond: json['plafond'] as int,
      );

  final int enLigne;
  final int plafond;

  int get restants => plafond - enLigne;
  bool get auPlafond => enLigne >= plafond;
}

/// Miroir mobile de `PaginatedResult<T>` (backend) pour `listActive()`.
class PaginatedPromos {
  PaginatedPromos(
      {required this.items,
      required this.total,
      required this.page,
      required this.limit});

  factory PaginatedPromos.fromJson(Map<String, dynamic> json) =>
      PaginatedPromos(
        items: (json['items'] as List<dynamic>)
            .map((e) => Promo.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        limit: json['limit'] as int,
      );

  final List<Promo> items;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => page * limit < total;
}

/// Miroir Dart de `PromoSortOrder` (backend, `list-promo-query.dto.ts`) —
/// une chaîne brute côté mobile ne serait pas vérifiée à la compilation en
/// cas de renommage backend (règle d'audit #19). Distinct de `PromoSort`
/// (`promo_providers.dart`), qui lui est un tri appliqué localement sur les
/// promos déjà chargées.
enum PromoServerSort {
  recent('recent'),
  discount('discount');

  const PromoServerSort(this.value);

  final String value;
}

class PromoApi {
  PromoApi(this._dio);

  final Dio _dio;

  /// Liste des promos actives (specs §3.1) : favoris d'abord, puis
  /// expiration la plus proche — tri appliqué côté backend. `page` permet le
  /// chargement incrémental ("Afficher plus" côté écran client).
  Future<PaginatedPromos> listActive({
    List<String> communeIds = const [],
    Categorie? categorie,
    List<String> favoriteIds = const [],
    int page = 1,
    String? search,
    String? commercantId,
    PromoServerSort? sort,
    int? limit,

    /// Point de recherche **enregistré par le client**, ou `null`.
    ///
    /// ⚠️ **La porte de consentement est ici, et nulle part ailleurs.**
    /// `null` veut dire « le client n'a rien enregistré, donc rien à
    /// transmettre » — et le serveur applique alors son propre défaut. Ne
    /// jamais y substituer une valeur de repli côté app : ce serait envoyer
    /// une position au nom d'un client qui n'en a donné aucune.
    ///
    /// ⚠️ Et **jamais la lecture du capteur GPS** : celle-ci reste sur
    /// l'appareil (centrage de la carte, distances affichées). Le seul chemin
    /// du capteur vers ce paramètre passe par un enregistrement explicite du
    /// client dans `ClientPositionStore`.
    (double, double)? point,
    double? radiusKm,

    /// Ne renvoyer que les favoris, **sans cadrage géographique**. Un favori
    /// est un choix explicite : une règle de proximité n'a pas à le retirer.
    bool favoritesOnly = false,
  }) async {
    final query = <String, dynamic>{
      if (communeIds.isNotEmpty) 'communeIds': communeIds.join(','),
      if (point != null) 'latitude': point.$1,
      if (point != null) 'longitude': point.$2,
      if (point != null && radiusKm != null) 'radiusKm': radiusKm,
      if (categorie != null) 'categorie': categorie.value,
      if (favoriteIds.isNotEmpty) 'favoriteIds': favoriteIds.join(','),
      if (favoritesOnly && favoriteIds.isNotEmpty) 'favoritesOnly': true,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (commercantId != null) 'commercantId': commercantId,
      if (sort != null) 'sort': sort.value,
      'page': page,
      'limit': limit ?? _activePageSize,
    };
    final response =
        await _dio.get<Map<String, dynamic>>('/promo', queryParameters: query);
    return PaginatedPromos.fromJson(response.data!);
  }

  /// Repères géographiques servis par le serveur : point par défaut, rayon par
  /// défaut, rayon maximum.
  ///
  /// ⚠️ **Ces valeurs ne sont jamais recopiées côté app.** Les compiler dans le
  /// binaire les figerait jusqu'à la prochaine publication sur les stores —
  /// alors qu'ici, changer le point par défaut est une ligne de `.env`. C'est
  /// le même contrat que `plafond` dans `GET /promo/me/slots`.
  Future<ClientGeoConfig> clientConfig() async {
    final response = await _dio.get<Map<String, dynamic>>('/promo/config');
    return ClientGeoConfig.fromJson(response.data!);
  }

  /// Commerçants géolocalisés de la zone visible de la carte, avec leurs
  /// promos actives. Pas de pagination : on ne peut pas afficher "la page 2"
  /// d'une carte — le backend plafonne et renvoie `truncated`.
  Future<MapShopsResult> listForMap({
    required double north,
    required double south,
    required double east,
    required double west,
    Categorie? categorie,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/promo/map',
      queryParameters: <String, dynamic>{
        'north': north,
        'south': south,
        'east': east,
        'west': west,
        if (categorie != null) 'categorie': categorie.value,
      },
    );
    return MapShopsResult.fromJson(response.data!);
  }

  /// Où centrer la carte pour les communes choisies, quand la position GPS
  /// n'est pas disponible.
  ///
  /// `null` quand le serveur ne connaît pas de centre — aucun commerçant
  /// positionné n'a de promo visible dans ces communes. C'est une réponse à
  /// part entière, pas un échec : l'appelant garde son propre repli plutôt que
  /// de recevoir un point inventé (règle #29).
  Future<({double latitude, double longitude})?> fetchMapCenter(
    List<String> communeIds,
  ) async {
    if (communeIds.isEmpty) return null;
    final response = await _dio.get<Map<String, dynamic>>(
      '/promo/map/center',
      queryParameters: <String, dynamic>{'communeIds': communeIds.join(',')},
    );
    final center = response.data!['center'] as Map<String, dynamic>?;
    if (center == null) return null;
    return (
      latitude: (center['latitude'] as num).toDouble(),
      longitude: (center['longitude'] as num).toDouble(),
    );
  }

  Future<Promo> detail(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/promo/$id');
    return Promo.fromJson(response.data!);
  }

  Future<Promo> create({
    required String description,
    required double prixAvant,
    required double prixApres,
    required Categorie categorie,
    required List<String> photoKeys,
    int? dureeJours,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo',
      data: _buildPayload(description, prixAvant, prixApres, categorie,
          photoKeys, dureeJours, asDraft),
    );
    return Promo.fromJson(response.data!);
  }

  Future<Promo> createForCommercant(
    String commercantId, {
    required String description,
    required double prixAvant,
    required double prixApres,
    required Categorie categorie,
    required List<String> photoKeys,
    int? dureeJours,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo/agent/$commercantId',
      data: _buildPayload(description, prixAvant, prixApres, categorie,
          photoKeys, dureeJours, asDraft),
    );
    return Promo.fromJson(response.data!);
  }

  /// Occupation du plafond, **mesurée par le serveur**.
  ///
  /// Elle était dérivée de [listMine] — une page de 100, tous statuts
  /// confondus — en comptant les `publiee`. Le commentaire justifiait cette
  /// page unique par « le plafond de 5 actives », que cet endpoint ne renvoie
  /// pas : au-delà de 100 promos cumulées, le tableau de bord annonçait des
  /// emplacements libres pendant que le serveur refusait en
  /// `PROMO_ACTIVE_CAP_REACHED` (revue 2026-08-05, règle #29).
  Future<PromoSlots> fetchSlots() async {
    final response = await _dio.get<Map<String, dynamic>>('/promo/me/slots');
    return PromoSlots.fromJson(response.data!);
  }

  Future<List<Promo>> listMine() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/promo/me/all',
      queryParameters: {'limit': _pageSize},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => Promo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> update(
    String id, {
    String? description,
    double? prixAvant,
    double? prixApres,
    Categorie? categorie,
    List<String>? photoKeys,
  }) async {
    await _dio.patch<void>('/promo/$id', data: {
      if (description != null) 'description': description,
      if (prixAvant != null) 'prixAvant': prixAvant,
      if (prixApres != null) 'prixApres': prixApres,
      if (categorie != null) 'categorie': categorie.value,
      if (photoKeys != null) 'photoKeys': photoKeys,
    });
  }

  /// Publie un brouillon, ou republie une promo arrêtée/expirée (nouvelle
  /// `dateFin` recalculée côté backend).
  Future<void> publish(String id) async {
    await _dio.post<void>('/promo/$id/publish');
  }

  /// Arrêt volontaire (ex. rupture de stock) — libère un slot sur le plafond de 5.
  Future<void> stop(String id) async {
    await _dio.post<void>('/promo/$id/stop');
  }

  Map<String, dynamic> _buildPayload(
    String description,
    double prixAvant,
    double prixApres,
    Categorie categorie,
    List<String> photoKeys,
    int? dureeJours,
    bool asDraft,
  ) =>
      {
        'description': description,
        'prixAvant': prixAvant,
        'prixApres': prixApres,
        'categorie': categorie.value,
        'photoKeys': photoKeys,
        // Une DUREE, jamais une date : l'app envoyait une `dateFin` calculee
        // sur l'horloge du telephone, que le serveur comparait a la sienne
        // sans tolerance — quelques minutes d'avance suffisaient a faire
        // refuser une duree pourtant legale, avec un message non traduit
        // (`PROMO_DATE_FIN_EXCEEDS_MAX`). La seule horloge qui compte est
        // celle qui valide (revue 2026-08-05).
        if (dureeJours != null) 'dureeJours': dureeJours,
        if (asDraft) 'asDraft': asDraft,
      };
}

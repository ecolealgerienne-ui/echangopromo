import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/map_shop.dart';
import '../../domain/models/promo.dart';

/// Le backend pagine `/promo` et `/promo/me/all` (`{items, total, page,
/// limit}`). `listMine()` reste une page unique généreuse (plafond métier de
/// 5 promos actives par commerçant, jamais approché).
const _pageSize = 100;

/// `listActive()` pagine réellement côté mobile via bouton "Afficher plus"
/// (retour terrain 2026-07-14 : grosses communes type Djelfa dépassant cette
/// taille en promos actives simultanées).
const _activePageSize = 50;

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
  }) async {
    final query = <String, dynamic>{
      if (communeIds.isNotEmpty) 'communeIds': communeIds.join(','),
      if (categorie != null) 'categorie': categorie.value,
      if (favoriteIds.isNotEmpty) 'favoriteIds': favoriteIds.join(','),
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
    DateTime? dateFin,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo',
      data: _buildPayload(description, prixAvant, prixApres, categorie,
          photoKeys, dateFin, asDraft),
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
    DateTime? dateFin,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo/agent/$commercantId',
      data: _buildPayload(description, prixAvant, prixApres, categorie,
          photoKeys, dateFin, asDraft),
    );
    return Promo.fromJson(response.data!);
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
    DateTime? dateFin,
    bool asDraft,
  ) =>
      {
        'description': description,
        'prixAvant': prixAvant,
        'prixApres': prixApres,
        'categorie': categorie.value,
        'photoKeys': photoKeys,
        if (dateFin != null) 'dateFin': dateFin.toIso8601String(),
        if (asDraft) 'asDraft': asDraft,
      };
}

import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/promo.dart';

/// Le backend pagine `/promo` et `/promo/me/all` (`{items, total, page,
/// limit}`). `listMine()` reste une page unique généreuse (plafond métier de
/// 5 promos actives par commerçant, jamais approché) ; `listActive()` pagine
/// réellement côté mobile via bouton "Afficher plus" (retour terrain
/// 2026-07-14 : grosses communes type Djelfa dépassant `_pageSize` en promos
/// actives simultanées).
const _pageSize = 100;

/// Miroir mobile de `PaginatedResult<T>` (backend) pour `listActive()`.
class PaginatedPromos {
  PaginatedPromos({required this.items, required this.total, required this.page, required this.limit});

  factory PaginatedPromos.fromJson(Map<String, dynamic> json) => PaginatedPromos(
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
  }) async {
    final query = <String, dynamic>{
      if (communeIds.isNotEmpty) 'communeIds': communeIds.join(','),
      if (categorie != null) 'categorie': categorie.value,
      if (favoriteIds.isNotEmpty) 'favoriteIds': favoriteIds.join(','),
      'page': page,
      'limit': _pageSize,
    };
    final response = await _dio.get<Map<String, dynamic>>('/promo', queryParameters: query);
    return PaginatedPromos.fromJson(response.data!);
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
      data: _buildPayload(description, prixAvant, prixApres, categorie, photoKeys, dateFin, asDraft),
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
      data: _buildPayload(description, prixAvant, prixApres, categorie, photoKeys, dateFin, asDraft),
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

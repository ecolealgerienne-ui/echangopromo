import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/promo.dart';

/// Le backend pagine désormais `/promo` et `/promo/me/all` (`{items, total,
/// page, limit}`) — le pilote (un seul quartier) reste largement sous cette
/// taille de page, donc on récupère une seule page généreuse plutôt que de
/// construire un vrai défilement infini pour l'instant. À revoir quand le
/// volume de promos actives approchera `_pageSize`.
const _pageSize = 100;

class PromoApi {
  PromoApi(this._dio);

  final Dio _dio;

  /// Liste des promos actives (specs §3.1) : favoris d'abord, puis
  /// expiration la plus proche — tri appliqué côté backend.
  Future<List<Promo>> listActive({
    List<String> communeIds = const [],
    Categorie? categorie,
    List<String> favoriteIds = const [],
  }) async {
    final query = <String, dynamic>{
      if (communeIds.isNotEmpty) 'communeIds': communeIds.join(','),
      if (categorie != null) 'categorie': categorie.value,
      if (favoriteIds.isNotEmpty) 'favoriteIds': favoriteIds.join(','),
      'limit': _pageSize,
    };
    final response = await _dio.get<Map<String, dynamic>>('/promo', queryParameters: query);
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => Promo.fromJson(e as Map<String, dynamic>)).toList();
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
    required String photoKey,
    DateTime? dateFin,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo',
      data: _buildPayload(description, prixAvant, prixApres, categorie, photoKey, dateFin, asDraft),
    );
    return Promo.fromJson(response.data!);
  }

  Future<Promo> createForCommercant(
    String commercantId, {
    required String description,
    required double prixAvant,
    required double prixApres,
    required Categorie categorie,
    required String photoKey,
    DateTime? dateFin,
    bool asDraft = false,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo/agent/$commercantId',
      data: _buildPayload(description, prixAvant, prixApres, categorie, photoKey, dateFin, asDraft),
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
    String? photoKey,
  }) async {
    await _dio.patch<void>('/promo/$id', data: {
      if (description != null) 'description': description,
      if (prixAvant != null) 'prixAvant': prixAvant,
      if (prixApres != null) 'prixApres': prixApres,
      if (categorie != null) 'categorie': categorie.value,
      if (photoKey != null) 'photoKey': photoKey,
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
    String photoKey,
    DateTime? dateFin,
    bool asDraft,
  ) =>
      {
        'description': description,
        'prixAvant': prixAvant,
        'prixApres': prixApres,
        'categorie': categorie.value,
        'photoKey': photoKey,
        if (dateFin != null) 'dateFin': dateFin.toIso8601String(),
        if (asDraft) 'asDraft': asDraft,
      };
}

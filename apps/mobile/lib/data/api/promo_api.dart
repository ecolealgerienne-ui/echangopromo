import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/promo.dart';

class PromoApi {
  PromoApi(this._dio);

  final Dio _dio;

  /// Liste des promos actives (specs §3.1) : favoris d'abord, puis
  /// expiration la plus proche — tri appliqué côté backend.
  Future<List<Promo>> listActive({
    String? communeId,
    Categorie? categorie,
    List<String> favoriteIds = const [],
  }) async {
    final query = <String, dynamic>{
      if (communeId != null) 'communeId': communeId,
      if (categorie != null) 'categorie': categorie.value,
      if (favoriteIds.isNotEmpty) 'favoriteIds': favoriteIds.join(','),
    };
    final response = await _dio.get<List<dynamic>>('/promo', queryParameters: query);
    return response.data!.map((e) => Promo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Promo> detail(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/promo/$id');
    return Promo.fromJson(response.data!);
  }

  Future<Promo> create({
    required String produit,
    required double prixAvant,
    required double prixApres,
    required Categorie categorie,
    required String photoKey,
    DateTime? dateFin,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo',
      data: _buildPayload(produit, prixAvant, prixApres, categorie, photoKey, dateFin),
    );
    return Promo.fromJson(response.data!);
  }

  Future<Promo> createForCommercant(
    String commercantId, {
    required String produit,
    required double prixAvant,
    required double prixApres,
    required Categorie categorie,
    required String photoKey,
    DateTime? dateFin,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/promo/agent/$commercantId',
      data: _buildPayload(produit, prixAvant, prixApres, categorie, photoKey, dateFin),
    );
    return Promo.fromJson(response.data!);
  }

  Future<List<Promo>> listMine() async {
    final response = await _dio.get<List<dynamic>>('/promo/me/all');
    return response.data!.map((e) => Promo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> update(
    String id, {
    String? produit,
    double? prixAvant,
    double? prixApres,
    Categorie? categorie,
    String? photoKey,
  }) async {
    await _dio.patch<void>('/promo/$id', data: {
      if (produit != null) 'produit': produit,
      if (prixAvant != null) 'prixAvant': prixAvant,
      if (prixApres != null) 'prixApres': prixApres,
      if (categorie != null) 'categorie': categorie.value,
      if (photoKey != null) 'photoKey': photoKey,
    });
  }

  Map<String, dynamic> _buildPayload(
    String produit,
    double prixAvant,
    double prixApres,
    Categorie categorie,
    String photoKey,
    DateTime? dateFin,
  ) =>
      {
        'produit': produit,
        'prixAvant': prixAvant,
        'prixApres': prixApres,
        'categorie': categorie.value,
        'photoKey': photoKey,
        if (dateFin != null) 'dateFin': dateFin.toIso8601String(),
      };
}

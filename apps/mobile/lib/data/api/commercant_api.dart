import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/commercant.dart';

class CommercantApi {
  CommercantApi(this._dio);

  final Dio _dio;

  Future<String> register({
    required String telephone,
    required String nom,
    String? adresse,
    required Categorie categorie,
    required String communeId,
    required String pin,
    String? photoKey,
    double? latitude,
    double? longitude,
    required bool acceptedTerms,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>('/commercant/register', data: {
      'telephone': telephone,
      'nom': nom,
      if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
      'categorie': categorie.value,
      'communeId': communeId,
      'pin': pin,
      if (photoKey != null) 'photoKey': photoKey,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'acceptedTerms': acceptedTerms,
    });
    return response.data!['accessToken'] as String;
  }

  /// Active un compte créé par un agent (ou réinitialisé par l'admin) — pas d'OTP.
  Future<String> claim({required String telephone, required String pin}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/commercant/claim',
      data: {'telephone': telephone, 'pin': pin},
    );
    return response.data!['accessToken'] as String;
  }

  Future<String> login({required String telephone, required String pin}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/commercant/login',
      data: {'telephone': telephone, 'pin': pin},
    );
    return response.data!['accessToken'] as String;
  }

  Future<Commercant> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/commercant/me');
    return Commercant.fromJson(response.data!);
  }

  /// Édition du profil — téléphone volontairement non modifiable ici.
  Future<Commercant> updateProfile({
    String? nom,
    String? adresse,
    Categorie? categorie,
    String? photoKey,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>('/commercant/me', data: {
      if (nom != null) 'nom': nom,
      if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
      if (categorie != null) 'categorie': categorie.value,
      if (photoKey != null) 'photoKey': photoKey,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return Commercant.fromJson(response.data!);
  }

  Future<Commercant> publicProfile(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/commercant/$id/public');
    return Commercant.fromJson(response.data!);
  }

  Future<int> dashboardProfileViewCount() async {
    final response = await _dio.get<Map<String, dynamic>>('/commercant/me/dashboard');
    return response.data!['profileViewCount'] as int;
  }

  Future<void> requestRegistreVerification(String registreKey) async {
    await _dio.post<void>('/commercant/me/registre', data: {'registreKey': registreKey});
  }

  /// Soft delete côté backend (deletedAt) — jamais de suppression physique.
  Future<void> deleteAccount() async {
    await _dio.delete<void>('/commercant/me');
  }
}

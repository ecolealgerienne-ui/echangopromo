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
    final response =
        await _dio.post<Map<String, dynamic>>('/commercant/register', data: {
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

  /// Libre-service : le commerçant connaît encore son PIN actuel et veut le
  /// changer (décision produit 2026-07-13 — contrairement au flux "PIN
  /// oublié", qui passe par un admin/agent). Le token courant devient
  /// invalide juste après cet appel (tokenVersion incrémenté côté service),
  /// à l'appelant de déconnecter et renvoyer vers l'écran de connexion.
  Future<void> changePin(
      {required String oldPin, required String newPin}) async {
    await _dio.patch<void>('/commercant/me/pin',
        data: {'oldPin': oldPin, 'newPin': newPin});
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
    final response =
        await _dio.patch<Map<String, dynamic>>('/commercant/me', data: {
      if (nom != null) 'nom': nom,
      if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
      if (categorie != null) 'categorie': categorie.value,
      if (photoKey != null) 'photoKey': photoKey,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return Commercant.fromJson(response.data!);
  }

  /// Pose la position du commerce, et **elle seule**.
  ///
  /// ⚠️ **Ne pas remplacer par `updateProfile(latitude:, longitude:)`.** Cette
  /// route-là remet le compte en revue de profil, et la revue **bloque la
  /// publication** : un commerçant à qui l'on vient de refuser une publication
  /// faute de position se retrouverait bloqué une seconde fois, à attendre un
  /// administrateur, pour avoir fait exactement ce qu'on lui demandait.
  ///
  /// Côté serveur, la dispense ne vaut que pour la **première** pose ; déplacer
  /// une position déjà renseignée reste une modification de profil.
  Future<Commercant> setPosition({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/commercant/me/position',
      data: {'latitude': latitude, 'longitude': longitude},
    );
    return Commercant.fromJson(response.data!);
  }

  Future<Commercant> publicProfile(String id) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/commercant/$id/public');
    return Commercant.fromJson(response.data!);
  }

  Future<int> dashboardProfileViewCount() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/commercant/me/dashboard');
    return response.data!['profileViewCount'] as int;
  }

  Future<void> requestRegistreVerification(String registreKey) async {
    await _dio.post<void>('/commercant/me/registre',
        data: {'registreKey': registreKey});
  }

  /// Soft delete côté backend (deletedAt) — jamais de suppression physique.
  Future<void> deleteAccount() async {
    await _dio.delete<void>('/commercant/me');
  }
}

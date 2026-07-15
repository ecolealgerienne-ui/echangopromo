import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/commercant.dart';

class AgentApi {
  AgentApi(this._dio);

  final Dio _dio;

  Future<String> login({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/agent/login',
      data: {'email': email, 'password': password},
    );
    return response.data!['accessToken'] as String;
  }

  Future<Agent> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/agent/me');
    return Agent.fromJson(response.data!);
  }

  Future<Commercant> createCommercant({
    required String telephone,
    required String nom,
    String? adresse,
    required Categorie categorie,
    required String communeId,
    required String pin,
    String? photoKey,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>('/agent/commercant', data: {
      'telephone': telephone,
      'nom': nom,
      if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
      'categorie': categorie.value,
      'communeId': communeId,
      'pin': pin,
      if (photoKey != null) 'photoKey': photoKey,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    });
    return Commercant.fromJson(response.data!);
  }
}

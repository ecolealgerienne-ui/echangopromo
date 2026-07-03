import 'package:dio/dio.dart';
import '../../domain/enums/categorie.dart';
import '../../domain/models/commercant.dart';

class CommercantApi {
  CommercantApi(this._dio);

  final Dio _dio;

  Future<void> register({
    required String telephone,
    required String nom,
    required String adresse,
    required Categorie categorie,
    required String communeId,
  }) async {
    await _dio.post<void>('/commercant/register', data: {
      'telephone': telephone,
      'nom': nom,
      'adresse': adresse,
      'categorie': categorie.value,
      'communeId': communeId,
    });
  }

  Future<String> confirmInscription({
    required String telephone,
    required String code,
    required String pin,
  }) =>
      _confirm('/commercant/confirm-inscription', telephone, code, pin);

  Future<String> confirmRevendication({
    required String telephone,
    required String code,
    required String pin,
  }) =>
      _confirm('/commercant/confirm-revendication', telephone, code, pin);

  Future<String> _confirm(String path, String telephone, String code, String pin) async {
    final response = await _dio.post<Map<String, dynamic>>(
      path,
      data: {'telephone': telephone, 'code': code, 'pin': pin},
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

  Future<void> forgotPinRequest(String telephone) async {
    await _dio.post<void>('/commercant/forgot-pin/request', data: {'telephone': telephone});
  }

  Future<void> forgotPinConfirm({
    required String telephone,
    required String code,
    required String newPin,
  }) async {
    await _dio.post<void>('/commercant/forgot-pin/confirm', data: {
      'telephone': telephone,
      'code': code,
      'newPin': newPin,
    });
  }

  Future<Commercant> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/commercant/me');
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
}

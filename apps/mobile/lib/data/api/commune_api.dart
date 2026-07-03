import 'package:dio/dio.dart';
import '../../domain/models/commune.dart';

class CommuneApi {
  CommuneApi(this._dio);

  final Dio _dio;

  Future<List<Commune>> list({String? wilaya}) async {
    final response = await _dio.get<List<dynamic>>(
      '/commune',
      queryParameters: wilaya != null ? {'wilaya': wilaya} : null,
    );
    return response.data!.map((e) => Commune.fromJson(e as Map<String, dynamic>)).toList();
  }
}

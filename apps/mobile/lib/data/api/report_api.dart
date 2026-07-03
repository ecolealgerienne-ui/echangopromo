import 'package:dio/dio.dart';

class ReportApi {
  ReportApi(this._dio);

  final Dio _dio;

  /// Signalement "promo expirée / incorrecte" — limité à 1 par device par
  /// promo côté backend (specs §5.4).
  Future<void> create(String promoId) async {
    await _dio.post<void>('/report', data: {'promoId': promoId});
  }
}

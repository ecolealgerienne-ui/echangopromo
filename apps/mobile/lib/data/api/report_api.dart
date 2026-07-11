import 'package:dio/dio.dart';
import '../../domain/enums/report_reason.dart';

class ReportApi {
  ReportApi(this._dio);

  final Dio _dio;

  /// Signalement "promo expirée / incorrecte" — limité à 1 par device par
  /// promo côté backend (specs §5.4). `reason` (plan de correction, Phase 5)
  /// donne à l'admin/agent un contexte de décision, pas seulement un compte.
  Future<void> create(String promoId, ReportReason reason) async {
    await _dio.post<void>('/report', data: {'promoId': promoId, 'reason': reason.value});
  }
}

import 'package:dio/dio.dart';
import '../../domain/enums/registre_status.dart';
import '../../domain/models/admin.dart';
import '../../domain/models/admin_commercant_item.dart';
import '../../domain/models/agent.dart';
import '../../domain/models/audit_log_entry.dart';
import '../../domain/models/moderation_item.dart';

/// Page unique généreuse plutôt qu'une vraie pagination UI — même décision
/// que `PromoApi` (pilote un seul quartier, volume largement sous ce seuil).
const _pageSize = 100;

class AdminApi {
  AdminApi(this._dio);

  final Dio _dio;

  Future<String> login({required String email, required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/login',
      data: {'email': email, 'password': password},
    );
    return response.data!['accessToken'] as String;
  }

  Future<Admin> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/admin/me');
    return Admin.fromJson(response.data!);
  }

  Future<
      ({
        int commercesActifs,
        int promosPubliees,
        int signalementsEnAttente,
        int registresEnAttente,
        int profilsEnAttente,
      })> dashboard() async {
    final response = await _dio.get<Map<String, dynamic>>('/admin/dashboard');
    final data = response.data!;
    return (
      commercesActifs: data['commercesActifs'] as int,
      promosPubliees: data['promosPubliees'] as int,
      signalementsEnAttente: data['signalementsEnAttente'] as int,
      registresEnAttente: data['registresEnAttente'] as int,
      profilsEnAttente: data['profilsEnAttente'] as int,
    );
  }

  // --- Modération ---

  Future<List<ModerationItem>> moderationQueue() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/moderation/queue',
      queryParameters: {'limit': _pageSize},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => ModerationItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> masquerPromo(String promoId) async {
    await _dio.post<void>('/admin/moderation/$promoId/masquer');
  }

  Future<void> verifierOkPromo(String promoId) async {
    await _dio.post<void>('/admin/moderation/$promoId/verifier-ok');
  }

  Future<void> avertirPromo(String promoId) async {
    await _dio.post<void>('/admin/moderation/$promoId/avertir');
  }

  /// Vue globale de toutes les promos (plan de correction, Phase 2) — pas
  /// seulement celles ayant atteint le seuil de signalements, pour pouvoir
  /// masquer un contenu problématique repéré directement.
  Future<List<ModerationItem>> listAllPromos({String? search}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/promo',
      queryParameters: {'limit': _pageSize, if (search != null && search.isNotEmpty) 'search': search},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => ModerationItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Commerçants (plan de correction, Phase 2) ---

  Future<List<AdminCommercantItem>> listCommercants({
    String? search,
    RegistreStatus? registreStatus,
    bool? profilePendingReview,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/commercant',
      queryParameters: {
        'limit': _pageSize,
        if (search != null && search.isNotEmpty) 'search': search,
        if (registreStatus != null) 'registreStatus': registreStatus.value,
        if (profilePendingReview != null) 'profilePendingReview': profilePendingReview,
      },
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => AdminCommercantItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> suspendCommercant(String commercantId) async {
    await _dio.post<void>('/admin/commercant/$commercantId/suspend');
  }

  Future<void> reactivateCommercant(String commercantId) async {
    await _dio.post<void>('/admin/commercant/$commercantId/reactivate');
  }

  // --- Registre ---

  Future<void> validerRegistre(String commercantId) async {
    await _dio.post<void>('/admin/commercant/$commercantId/registre/valider');
  }

  Future<void> rejeterRegistre(String commercantId) async {
    await _dio.post<void>('/admin/commercant/$commercantId/registre/rejeter');
  }

  /// PIN vraiment oublié — fixe directement un nouveau PIN (décision produit
  /// 2026-07-13), à communiquer au commerçant par téléphone.
  Future<void> resetPin(String commercantId, String newPin) async {
    await _dio.post<void>(
      '/admin/commercant/$commercantId/reset-pin',
      data: {'newPin': newPin},
    );
  }

  /// Le commerçant connaît encore son PIN actuel et veut le changer.
  Future<void> changePin(String commercantId, String oldPin, String newPin) async {
    await _dio.post<void>(
      '/admin/commercant/$commercantId/change-pin',
      data: {'oldPin': oldPin, 'newPin': newPin},
    );
  }

  Future<void> validerProfil(String commercantId) async {
    await _dio.post<void>('/admin/commercant/$commercantId/profile/valider');
  }

  // --- Agents ---

  Future<List<Agent>> listAgents() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/agent',
      queryParameters: {'limit': _pageSize},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => Agent.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Agent> createAgent({
    required String email,
    required String password,
    required String nom,
    List<String>? communeIds,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>('/admin/agent', data: {
      'email': email,
      'password': password,
      'nom': nom,
      if (communeIds != null) 'communeIds': communeIds,
    });
    return Agent.fromJson(response.data!);
  }

  Future<void> assignCommunes({required String agentId, required List<String> communeIds}) async {
    await _dio.patch<void>('/admin/agent/$agentId/communes', data: {'communeIds': communeIds});
  }

  Future<void> revokeAgentToken(String agentId) async {
    await _dio.post<void>('/admin/agent/$agentId/revoke-token');
  }

  Future<void> transferCommunes({
    required List<String> communeIds,
    required String fromAgentId,
    required String toAgentId,
  }) async {
    await _dio.post<void>('/admin/agent/transfer-communes', data: {
      'communeIds': communeIds,
      'fromAgentId': fromAgentId,
      'toAgentId': toAgentId,
    });
  }

  // --- Journal d'audit (plan de correction, Phase 3) ---

  Future<List<AuditLogEntry>> auditLog() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/audit-log',
      queryParameters: {'limit': _pageSize},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items.map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>)).toList();
  }
}

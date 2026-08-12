import 'package:dio/dio.dart';
import '../../domain/models/highlight.dart';

/// Bandeau « Top promos » de l'accueil : lecture publique, gestion admin.
///
/// Les deux vivent ici plutôt que côté `AdminApi` : elles partagent le même
/// modèle de sortie ([Highlight]) et la même notion de diapositive — les
/// séparer obligerait à dupliquer le parsing.
class HighlightApi {
  HighlightApi(this._dio);

  final Dio _dio;

  /// Ce que voit le client. Retourne toujours quelque chose tant qu'il
  /// existe des promos actives : sans mise en avant admin exploitable, le
  /// backend retombe sur le classement calculé (`curated: false`).
  /// [point] cadre le **repli** calculé, pas la curation admin (globale par
  /// décision produit). Même porte de consentement que la liste : `null` veut
  /// dire « le client n'a rien enregistré », et le serveur cadre alors sur son
  /// propre défaut — jamais sur tout le pays, ce qui ferait annoncer en vitrine
  /// des promos que la liste juste en dessous ne contient pas.
  Future<List<Highlight>> list({
    (double, double)? point,
    double? radiusKm,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/highlight',
      queryParameters: {
        if (point != null) 'latitude': point.$1,
        if (point != null) 'longitude': point.$2,
        if (point != null && radiusKm != null) 'radiusKm': radiusKm,
      },
    );
    final items = response.data!['items'] as List<dynamic>;
    return items
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // --- Admin ---

  /// Toutes les diapositives, inactives comprises, dans l'ordre du bandeau.
  Future<List<Highlight>> listForAdmin() async {
    final response = await _dio.get<Map<String, dynamic>>('/admin/highlight');
    final items = response.data!['items'] as List<dynamic>;
    return items
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Highlight> create({
    String? promoId,
    String? imageKey,
    String? titre,
    String? sousTitre,
    bool? active,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>('/admin/highlight', data: {
      if (promoId != null) 'promoId': promoId,
      if (imageKey != null) 'imageKey': imageKey,
      if (titre != null && titre.isNotEmpty) 'titre': titre,
      if (sousTitre != null && sousTitre.isNotEmpty) 'sousTitre': sousTitre,
      if (active != null) 'active': active,
    });
    return Highlight.fromJson(response.data!);
  }

  /// Patch partiel : un champ absent du corps reste inchangé côté backend.
  ///
  /// Effacer passe par les drapeaux `clearPromo`/`clearImage`, pas par une
  /// valeur `null` : le backend ne peut pas distinguer un `null` envoyé d'un
  /// champ absent (voir `UpdateHighlightDto`). Pour les textes, la chaîne
  /// vide vaut effacement.
  Future<Highlight> update(
    String id, {
    String? promoId,
    String? imageKey,
    String? titre,
    String? sousTitre,
    bool? active,
    bool clearPromo = false,
    bool clearImage = false,
  }) async {
    final response =
        await _dio.patch<Map<String, dynamic>>('/admin/highlight/$id', data: {
      if (clearPromo)
        'clearPromo': true
      else if (promoId != null)
        'promoId': promoId,
      if (clearImage)
        'clearImage': true
      else if (imageKey != null)
        'imageKey': imageKey,
      if (titre != null) 'titre': titre,
      if (sousTitre != null) 'sousTitre': sousTitre,
      if (active != null) 'active': active,
    });
    return Highlight.fromJson(response.data!);
  }

  Future<void> delete(String id) async {
    await _dio.delete<void>('/admin/highlight/$id');
  }

  /// Ordre complet, jamais un déplacement relatif — le backend refuse une
  /// liste partielle (`HIGHLIGHT_REORDER_MISMATCH`).
  Future<List<Highlight>> reorder(List<String> ids) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/highlight/reorder',
      data: {'ids': ids},
    );
    final items = response.data!['items'] as List<dynamic>;
    return items
        .map((e) => Highlight.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

import '../enums/categorie.dart';
import '../enums/promo_lifecycle_status.dart';
import '../enums/promo_moderation_status.dart';

/// Entrée de la file de modération admin/agent (promo signalée, `GET
/// /admin/moderation/queue`) ou de la vue globale (`GET /admin/promo`,
/// plan de correction Phase 2) — même DTO backend (`toAdminPromoJson`),
/// `activeReportCount` n'est renseigné que pour la file automatique.
class ModerationItem {
  const ModerationItem({
    required this.id,
    required this.description,
    required this.prixAvant,
    required this.prixApres,
    required this.categorie,
    required this.photoUrls,
    this.thumbnailUrl,
    required this.lifecycleStatus,
    required this.moderationStatus,
    required this.commercantId,
    required this.commercantNom,
    required this.commercantTelephone,
    this.activeReportCount,
    this.reasonBreakdown,
  });

  factory ModerationItem.fromJson(Map<String, dynamic> json) => ModerationItem(
        id: json['id'] as String,
        description: json['description'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        categorie: Categorie.fromValue(json['categorie'] as String),
        photoUrls: (json['photoUrls'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        lifecycleStatus: PromoLifecycleStatus.fromValue(json['lifecycleStatus'] as String),
        moderationStatus: PromoModerationStatus.fromValue(json['moderationStatus'] as String),
        commercantId: json['commercantId'] as String,
        commercantNom: json['commercantNom'] as String,
        commercantTelephone: json['commercantTelephone'] as String,
        activeReportCount: json['activeReportCount'] as int?,
        reasonBreakdown: (json['reasonBreakdown'] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, value as int)),
      );

  final String id;
  final String description;
  final double prixAvant;
  final double prixApres;
  final Categorie categorie;
  final List<String> photoUrls;

  /// Miniature (~240px) de la 1ère photo — à utiliser à la place de
  /// [photoUrl] pour la vignette liste (`PromoModerationTile`).
  final String? thumbnailUrl;
  final PromoLifecycleStatus lifecycleStatus;
  final PromoModerationStatus moderationStatus;
  final String commercantId;
  final String commercantNom;
  final String commercantTelephone;
  final int? activeReportCount;

  /// Photo principale — seule affichée en liste (`PromoModerationTile`).
  String? get photoUrl => photoUrls.isEmpty ? null : photoUrls.first;

  /// Répartition des motifs de signalement actifs (plan de correction,
  /// Phase 5) — clé = valeur brute de `ReportReason` (ex. `'arnaque'`),
  /// renseignée uniquement pour la file automatique.
  final Map<String, int>? reasonBreakdown;
}

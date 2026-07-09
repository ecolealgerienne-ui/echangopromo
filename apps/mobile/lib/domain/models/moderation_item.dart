/// Entrée de la file de modération admin (promo signalée) — `GET
/// /admin/moderation/queue`, DTO dédié côté backend (pas l'entité Promo
/// brute, voir admin.controller.ts).
class ModerationItem {
  const ModerationItem({
    required this.id,
    required this.description,
    required this.prixAvant,
    required this.prixApres,
    required this.photoUrl,
    required this.activeReportCount,
    required this.commercantId,
    required this.commercantNom,
    required this.commercantTelephone,
  });

  factory ModerationItem.fromJson(Map<String, dynamic> json) => ModerationItem(
        id: json['id'] as String,
        description: json['description'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        photoUrl: json['photoUrl'] as String?,
        activeReportCount: json['activeReportCount'] as int,
        commercantId: json['commercantId'] as String,
        commercantNom: json['commercantNom'] as String,
        commercantTelephone: json['commercantTelephone'] as String,
      );

  final String id;
  final String description;
  final double prixAvant;
  final double prixApres;
  final String? photoUrl;
  final int activeReportCount;
  final String commercantId;
  final String commercantNom;
  final String commercantTelephone;
}

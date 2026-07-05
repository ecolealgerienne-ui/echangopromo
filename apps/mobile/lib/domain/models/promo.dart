import '../enums/categorie.dart';
import '../enums/promo_lifecycle_status.dart';
import '../enums/promo_moderation_status.dart';

class Promo {
  const Promo({
    required this.id,
    required this.commercantId,
    this.commercantNom,
    required this.description,
    required this.prixAvant,
    required this.prixApres,
    required this.categorie,
    required this.dateFin,
    required this.lifecycleStatus,
    required this.moderationStatus,
    required this.photoUrl,
    this.viewCount,
  });

  factory Promo.fromJson(Map<String, dynamic> json) => Promo(
        id: json['id'] as String,
        commercantId: json['commercantId'] as String,
        commercantNom: json['commercantNom'] as String?,
        description: json['description'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        categorie: Categorie.fromValue(json['categorie'] as String),
        dateFin: json['dateFin'] != null ? DateTime.parse(json['dateFin'] as String) : null,
        lifecycleStatus: PromoLifecycleStatus.fromValue(json['lifecycleStatus'] as String),
        moderationStatus: PromoModerationStatus.fromValue(json['moderationStatus'] as String),
        photoUrl: json['photoUrl'] as String?,
        viewCount: json['viewCount'] as int?,
      );

  final String id;
  final String commercantId;
  final String? commercantNom;
  final String description;
  final double prixAvant;
  final double prixApres;
  final Categorie categorie;

  /// Null tant que la promo est en brouillon (pas encore publiée).
  final DateTime? dateFin;
  final PromoLifecycleStatus lifecycleStatus;
  final PromoModerationStatus moderationStatus;
  final String? photoUrl;
  final int? viewCount;

  bool get isDraft => lifecycleStatus == PromoLifecycleStatus.brouillon;
  bool get isPublished => lifecycleStatus == PromoLifecycleStatus.publiee;
  bool get isStopped => lifecycleStatus == PromoLifecycleStatus.arretee;
  bool get isExpired =>
      lifecycleStatus == PromoLifecycleStatus.expiree ||
      (dateFin != null && dateFin!.isBefore(DateTime.now()));
}

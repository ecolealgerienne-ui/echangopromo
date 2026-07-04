import '../enums/categorie.dart';

class Promo {
  const Promo({
    required this.id,
    required this.commercantId,
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
        description: json['description'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        categorie: Categorie.fromValue(json['categorie'] as String),
        dateFin: json['dateFin'] != null ? DateTime.parse(json['dateFin'] as String) : null,
        lifecycleStatus: json['lifecycleStatus'] as String,
        moderationStatus: json['moderationStatus'] as String,
        photoUrl: json['photoUrl'] as String?,
        viewCount: json['viewCount'] as int?,
      );

  final String id;
  final String commercantId;
  final String description;
  final double prixAvant;
  final double prixApres;
  final Categorie categorie;

  /// Null tant que la promo est en brouillon (pas encore publiée).
  final DateTime? dateFin;
  final String lifecycleStatus;
  final String moderationStatus;
  final String? photoUrl;
  final int? viewCount;

  bool get isDraft => lifecycleStatus == 'brouillon';
  bool get isPublished => lifecycleStatus == 'publiee';
  bool get isStopped => lifecycleStatus == 'arretee';
  bool get isExpired =>
      lifecycleStatus == 'expiree' || (dateFin != null && dateFin!.isBefore(DateTime.now()));

  String get lifecycleLabel {
    switch (lifecycleStatus) {
      case 'brouillon':
        return 'Brouillon';
      case 'publiee':
        return isExpired ? 'Expirée' : 'Publiée';
      case 'arretee':
        return 'Arrêtée';
      case 'expiree':
        return 'Expirée';
      default:
        return lifecycleStatus;
    }
  }
}

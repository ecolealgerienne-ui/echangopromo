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
    required this.photoUrls,
    this.thumbnailUrl,
    this.photoKeys,
    this.viewCount,
    required this.createdAt,
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
        photoUrls: (json['photoUrls'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        photoKeys: (json['photoKeys'] as List<dynamic>?)?.map((e) => e as String).toList(),
        viewCount: json['viewCount'] as int?,
        createdAt: DateTime.parse(json['createdAt'] as String),
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
  final List<String> photoUrls;

  /// Miniature (~240px) de la 1ère photo, générée côté serveur — à utiliser
  /// pour toute vignette liste (`PromoCard`, `MyPromosScreen`...), jamais
  /// pour la fiche détail (`PromoPhotoHero`, pleine résolution). Retombe
  /// déjà sur la photo complète côté backend si la génération a échoué,
  /// donc non-null dès qu'il y a au moins une photo.
  final String? thumbnailUrl;

  /// Clés S3 brutes, dans le même ordre que [photoUrls] — renseignées
  /// uniquement par `GET /promo/me/all` (propriétaire authentifié), jamais
  /// par la liste/fiche publique. Utilisées par l'écran d'édition pour
  /// renvoyer les photos inchangées sans les réuploader (voir
  /// `PromoFormScreen`) ; `null` partout ailleurs.
  final List<String>? photoKeys;
  final int? viewCount;
  final DateTime createdAt;

  /// Photo principale (première de [photoUrls]) — c'est la seule affichée en
  /// liste/vignette, les écrans qui n'ont besoin que d'un aperçu unique
  /// (`PromoCard`, `MyPromosScreen`...) n'ont donc rien à changer.
  String? get photoUrl => photoUrls.isEmpty ? null : photoUrls.first;

  bool get isDraft => lifecycleStatus == PromoLifecycleStatus.brouillon;
  bool get isPublished => lifecycleStatus == PromoLifecycleStatus.publiee;
  bool get isStopped => lifecycleStatus == PromoLifecycleStatus.arretee;
  bool get isExpired =>
      lifecycleStatus == PromoLifecycleStatus.expiree ||
      (dateFin != null && dateFin!.isBefore(DateTime.now()));

  /// Même fenêtre que `PromoService.notifyExpiringSoonCron` côté backend —
  /// une seule définition de "bientôt" dans tout le produit.
  bool get isExpiringSoon =>
      !isExpired && dateFin != null && dateFin!.isBefore(DateTime.now().add(const Duration(hours: 24)));

  double get discountPercent => (prixAvant - prixApres) / prixAvant * 100;
}

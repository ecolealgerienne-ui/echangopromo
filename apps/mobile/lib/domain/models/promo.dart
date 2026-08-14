import '../enums/categorie.dart';
import '../enums/promo_lifecycle_status.dart';
import '../enums/promo_moderation_status.dart';
import '../promo_rules.dart';

class Promo {
  const Promo({
    required this.id,
    required this.commercantId,
    this.commercantNom,
    this.commercantLatitude,
    this.commercantLongitude,
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
    this.publishedAt,
  });

  factory Promo.fromJson(Map<String, dynamic> json) => Promo(
        id: json['id'] as String,
        commercantId: json['commercantId'] as String,
        commercantNom: json['commercantNom'] as String?,
        commercantLatitude: (json['commercantLatitude'] as num?)?.toDouble(),
        commercantLongitude: (json['commercantLongitude'] as num?)?.toDouble(),
        description: json['description'] as String,
        prixAvant: double.parse(json['prixAvant'].toString()),
        prixApres: double.parse(json['prixApres'].toString()),
        categorie: Categorie.fromValue(json['categorie'] as String),
        dateFin: json['dateFin'] != null
            ? DateTime.parse(json['dateFin'] as String)
            : null,
        lifecycleStatus:
            PromoLifecycleStatus.fromValue(json['lifecycleStatus'] as String),
        moderationStatus:
            PromoModerationStatus.fromValue(json['moderationStatus'] as String),
        photoUrls: (json['photoUrls'] as List<dynamic>? ?? const [])
            .map((e) => e as String)
            .toList(),
        thumbnailUrl: json['thumbnailUrl'] as String?,
        photoKeys: (json['photoKeys'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
        viewCount: json['viewCount'] as int?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        publishedAt: json['publishedAt'] != null
            ? DateTime.parse(json['publishedAt'] as String)
            : null,
      );

  final String id;
  final String commercantId;
  final String? commercantNom;

  /// Position du commerce, servie par `GET /promo` **pour que la liste puisse
  /// afficher la distance** (bascule 2026-08-12, A7 du plan).
  ///
  /// ⚠️ Ces deux champs étaient servis par le serveur et **jetés ici** : le
  /// modèle ne les lisait pas, donc `PromoCard` ne pouvait rien afficher, donc
  /// `formatDistance` n'était appelé que par la fiche et la carte. Une capacité
  /// écrite, documentée côté serveur, et sans appelant — règle 31, et elle ne
  /// produit aucune erreur : juste une fonctionnalité absente que personne ne
  /// cherche, puisque le code existe des deux côtés.
  ///
  /// ⚠️ `num?` et non `double?` au décodage : un entier JSON (`3`) arrive en
  /// `int` et un `as double?` planterait. Même piège que les prix, qui passent
  /// par `double.parse(...toString())` deux lignes plus bas.
  final double? commercantLatitude;
  final double? commercantLongitude;
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

  /// Horodatage de la (dernière) publication — posé uniquement par
  /// `publish()` côté backend, distinct de [createdAt] (peut dater d'un
  /// brouillon créé bien avant sa publication). `null` tant que la promo
  /// n'a jamais été publiée (toujours en brouillon).
  final DateTime? publishedAt;

  /// Photo principale (première de [photoUrls]) — c'est la seule affichée en
  /// liste/vignette, les écrans qui n'ont besoin que d'un aperçu unique
  /// (`PromoCard`, `MyPromosScreen`...) n'ont donc rien à changer.
  String? get photoUrl => photoUrls.isEmpty ? null : photoUrls.first;

  bool get isDraft => lifecycleStatus == PromoLifecycleStatus.brouillon;
  bool get isPublished => lifecycleStatus == PromoLifecycleStatus.publiee;
  bool get isStopped => lifecycleStatus == PromoLifecycleStatus.arretee;
  bool get isDeleted => lifecycleStatus == PromoLifecycleStatus.supprimee;
  bool get isExpired =>
      promoEstExpiree(lifecycleStatus: lifecycleStatus, dateFin: dateFin);

  /// Copie de `EXPIRING_SOON_WINDOW_HOURS` (`PromoService`, backend), qui pilote
  /// la notification « expire bientôt ».
  ///
  /// ⚠️ Le commentaire disait « une seule définition de "bientôt" dans tout le
  /// produit ». Il y en avait deux, et **une phrase ne tient pas un
  /// invariant** : changer la cadence du cron aurait allumé ce badge sans
  /// notification correspondante (revue 2026-08-05, règle #30). Les deux
  /// valeurs sont nommées et comparées par `tool/check_server_rules.dart`.
  bool get isExpiringSoon =>
      !isExpired &&
      dateFin != null &&
      dateFin!.isBefore(
          DateTime.now().add(const Duration(hours: promoExpiringSoonHours)));

  double get discountPercent => (prixAvant - prixApres) / prixAvant * 100;
}

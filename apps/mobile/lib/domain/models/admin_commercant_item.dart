import '../enums/categorie.dart';
import '../enums/commercant_account_state.dart';
import '../enums/commercant_origin_verification.dart';
import '../enums/registre_status.dart';

/// Entrée de la liste admin des commerçants (`GET /admin/commercant`, plan
/// de correction Phase 2) — recherche + gestion de compte (suspendre/
/// réactiver) et, depuis le 2026-07-11, consultation/validation du registre
/// (fusionné ici, l'ancienne file dédiée a été retirée).
class AdminCommercantItem {
  const AdminCommercantItem({
    required this.id,
    required this.nom,
    required this.telephone,
    this.adresse,
    required this.categorie,
    this.photoUrl,
    this.latitude,
    this.longitude,
    this.promoActiveCap,
    required this.accountState,
    required this.originVerification,
    required this.registreStatus,
    this.registreUrl,
    this.profilePendingReview = false,
    required this.suspended,
    required this.deleted,
    required this.createdAt,
  });

  factory AdminCommercantItem.fromJson(Map<String, dynamic> json) =>
      AdminCommercantItem(
        id: json['id'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        adresse: json['adresse'] as String?,
        categorie: Categorie.fromValue(json['categorie'] as String),
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        promoActiveCap: (json['promoActiveCap'] as num?)?.toInt(),
        accountState:
            CommercantAccountState.fromValue(json['accountState'] as String),
        originVerification: CommercantOriginVerification.fromValue(
            json['originVerification'] as String?),
        registreStatus:
            RegistreStatus.fromValue(json['registreStatus'] as String?),
        registreUrl: json['registreUrl'] as String?,
        profilePendingReview: json['profilePendingReview'] as bool? ?? false,
        suspended: json['suspended'] as bool,
        deleted: json['deleted'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String nom;
  final String telephone;
  final String? adresse;
  final Categorie categorie;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;

  /// Plafond de promos actives propre à ce commerçant, ou `null` s'il suit le
  /// réglage global du serveur.
  ///
  /// ⚠️ `null` n'est pas zéro : il dit « suit le défaut ». L'écran affiche donc
  /// deux textes distincts, pas un chiffre dans les deux cas — sinon on ne
  /// saurait plus si ce commerçant a été réglé ou non.
  final int? promoActiveCap;
  final CommercantAccountState accountState;
  final CommercantOriginVerification? originVerification;
  final RegistreStatus? registreStatus;
  final String? registreUrl;

  /// Toute modification de profil bloque la publication de promo jusqu'à
  /// validation admin — s'applique à tous les commerçants (décision produit
  /// 2026-07-12).
  final bool profilePendingReview;
  final bool suspended;

  /// Suppression logique (2026-07-14) — distincte de `suspended` : libère
  /// le numéro de téléphone et "supprime" les promos, pas de restauration
  /// prévue (contrairement à la suspension, réversible).
  final bool deleted;
  final DateTime createdAt;
}

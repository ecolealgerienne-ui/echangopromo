import '../enums/categorie.dart';
import '../enums/commercant_account_state.dart';
import '../enums/commercant_origin_verification.dart';
import '../enums/registre_status.dart';

class Commercant {
  const Commercant({
    required this.id,
    required this.nom,
    this.adresse,
    required this.categorie,
    required this.communeId,
    this.accountState,
    this.originVerification,
    this.registreStatus,
    this.profilePendingReview = false,
    this.telephone,
    this.photoUrl,
    this.latitude,
    this.longitude,
  });

  factory Commercant.fromJson(Map<String, dynamic> json) => Commercant(
        id: json['id'] as String,
        nom: json['nom'] as String,
        adresse: json['adresse'] as String?,
        categorie: Categorie.fromValue(json['categorie'] as String),
        communeId: json['communeId'] as String,
        accountState: json['accountState'] != null
            ? CommercantAccountState.fromValue(json['accountState'] as String)
            : null,
        originVerification:
            CommercantOriginVerification.fromValue(json['originVerification'] as String?),
        registreStatus: RegistreStatus.fromValue(json['registreStatus'] as String?),
        profilePendingReview: json['profilePendingReview'] as bool? ?? false,
        telephone: json['telephone'] as String?,
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  final String id;
  final String nom;
  final String? adresse;
  final Categorie categorie;
  final String communeId;
  final CommercantAccountState? accountState;
  final CommercantOriginVerification? originVerification;
  final RegistreStatus? registreStatus;

  /// Toute modification de profil bloque la publication de promo jusqu'à
  /// validation admin — s'applique à tous les commerçants, contrairement au
  /// blocage registre (décision produit 2026-07-12).
  final bool profilePendingReview;
  final String? telephone;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
}

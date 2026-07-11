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
    required this.communeId,
    this.photoUrl,
    this.latitude,
    this.longitude,
    required this.accountState,
    required this.originVerification,
    required this.registreStatus,
    this.registreUrl,
    required this.suspended,
    required this.createdAt,
  });

  factory AdminCommercantItem.fromJson(Map<String, dynamic> json) => AdminCommercantItem(
        id: json['id'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        adresse: json['adresse'] as String?,
        categorie: Categorie.fromValue(json['categorie'] as String),
        communeId: json['communeId'] as String,
        photoUrl: json['photoUrl'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        accountState: CommercantAccountState.fromValue(json['accountState'] as String),
        originVerification:
            CommercantOriginVerification.fromValue(json['originVerification'] as String?),
        registreStatus: RegistreStatus.fromValue(json['registreStatus'] as String?),
        registreUrl: json['registreUrl'] as String?,
        suspended: json['suspended'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String nom;
  final String telephone;
  final String? adresse;
  final Categorie categorie;
  final String communeId;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final CommercantAccountState accountState;
  final CommercantOriginVerification? originVerification;
  final RegistreStatus? registreStatus;
  final String? registreUrl;
  final bool suspended;
  final DateTime createdAt;
}

import '../enums/commercant_account_state.dart';
import '../enums/registre_status.dart';

/// Entrée de la liste admin des commerçants (`GET /admin/commercant`, plan
/// de correction Phase 2) — recherche + gestion de compte (suspendre/
/// réactiver), distincte de la file registre (en attente uniquement).
class AdminCommercantItem {
  const AdminCommercantItem({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.communeId,
    required this.accountState,
    required this.registreStatus,
    required this.suspended,
    required this.createdAt,
  });

  factory AdminCommercantItem.fromJson(Map<String, dynamic> json) => AdminCommercantItem(
        id: json['id'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        communeId: json['communeId'] as String,
        accountState: CommercantAccountState.fromValue(json['accountState'] as String),
        registreStatus: RegistreStatus.fromValue(json['registreStatus'] as String?),
        suspended: json['suspended'] as bool,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String nom;
  final String telephone;
  final String communeId;
  final CommercantAccountState accountState;
  final RegistreStatus? registreStatus;
  final bool suspended;
  final DateTime createdAt;
}

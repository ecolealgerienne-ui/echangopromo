import '../enums/audit_actor_type.dart';

/// Entrée du journal d'audit (`GET /admin/audit-log`, plan de correction
/// Phase 3) — traçabilité des actions agent/admin (modération, reset PIN,
/// suspension, suppression...).
///
/// ⚠️ L'exemple cité ici était « transfert de communes », une route supprimée
/// le 2026-08-13. Le même jour, ce journal est devenu **le seul contrepoids à
/// la portée globale de l'agent** : les quatorze gardes d'appartenance sont
/// tombées, il n'y a plus de limite *a priori*, seulement cette trace.
///
/// ⚠️ `actorLabel` et `targetLabel` peuvent être `null` — l'acteur ou la cible
/// n'a pas pu être résolu. **Ce n'est pas une chaîne vide à afficher telle
/// quelle** : le serveur refuse d'inventer un libellé (« agent supprimé » ferait
/// passer « je ne sais pas » pour « il n'existe plus »), et l'écran retombe
/// alors sur l'UUID, seule vérité disponible.
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorType,
    required this.actorId,
    required this.actorLabel,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        actorType: AuditActorType.fromValue(json['actorType'] as String),
        actorId: json['actorId'] as String,
        actorLabel: json['actorLabel'] as String?,
        action: json['action'] as String,
        targetType: json['targetType'] as String?,
        targetId: json['targetId'] as String?,
        targetLabel: json['targetLabel'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final AuditActorType actorType;
  final String actorId;
  final String? actorLabel;
  final String action;
  final String? targetType;
  final String? targetId;
  final String? targetLabel;
  final DateTime createdAt;
}

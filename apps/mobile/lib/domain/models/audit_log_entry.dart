import '../enums/audit_actor_type.dart';

/// Entrée du journal d'audit (`GET /admin/audit-log`, plan de correction
/// Phase 3) — traçabilité des actions agent/admin (transfert de communes,
/// modération, reset PIN...).
class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.actorType,
    required this.actorId,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as String,
        actorType: AuditActorType.fromValue(json['actorType'] as String),
        actorId: json['actorId'] as String,
        action: json['action'] as String,
        targetType: json['targetType'] as String?,
        targetId: json['targetId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final AuditActorType actorType;
  final String actorId;
  final String action;
  final String? targetType;
  final String? targetId;
  final DateTime createdAt;
}

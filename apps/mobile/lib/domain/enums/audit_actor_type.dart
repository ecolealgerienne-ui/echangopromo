/// Miroir de `AuditActorType` (backend) — CLAUDE.md règle #19.
enum AuditActorType {
  agent('agent'),
  admin('admin');

  const AuditActorType(this.value);

  final String value;

  static AuditActorType fromValue(String value) =>
      AuditActorType.values.firstWhere((t) => t.value == value);
}

/// Miroir de `CommercantOriginVerification` (backend) — indépendant du
/// cycle de vie du compte (CLAUDE.md règle #19).
enum CommercantOriginVerification {
  autoInscrit('auto_inscrit'),
  confirmeAgent('confirme_agent');

  const CommercantOriginVerification(this.value);

  final String value;

  static CommercantOriginVerification? fromValue(String? value) => value == null
      ? null
      : CommercantOriginVerification.values.firstWhere((s) => s.value == value);
}

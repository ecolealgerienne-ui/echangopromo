/// Miroir de `RegistreStatus` (backend) — badge `vérifié_registre`,
/// indépendant du cycle de vie du compte (CLAUDE.md règle #19).
enum RegistreStatus {
  enAttente('en_attente'),
  valide('valide'),
  rejete('rejete');

  const RegistreStatus(this.value);

  final String value;

  static RegistreStatus? fromValue(String? value) =>
      value == null ? null : RegistreStatus.values.firstWhere((s) => s.value == value);
}

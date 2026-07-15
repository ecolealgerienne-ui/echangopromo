/// Miroir de `PromoLifecycleStatus` (backend) — cycle de vie éditorial,
/// volontairement séparé du statut de modération (CLAUDE.md règle #8).
enum PromoLifecycleStatus {
  brouillon('brouillon'),
  publiee('publiee'),
  arretee('arretee'),
  expiree('expiree'),
  supprimee('supprimee');

  const PromoLifecycleStatus(this.value);

  final String value;

  static PromoLifecycleStatus fromValue(String value) => PromoLifecycleStatus.values
      .firstWhere((s) => s.value == value, orElse: () => PromoLifecycleStatus.expiree);
}

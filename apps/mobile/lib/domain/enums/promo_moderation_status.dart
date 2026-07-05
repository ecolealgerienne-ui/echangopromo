/// Miroir de `PromoModerationStatus` (backend) — indépendant du cycle de vie
/// (CLAUDE.md règle #8).
enum PromoModerationStatus {
  normale('normale'),
  signalee('signalee'),
  masquee('masquee'),
  verifieeOk('verifiee_ok');

  const PromoModerationStatus(this.value);

  final String value;

  static PromoModerationStatus fromValue(String value) => PromoModerationStatus.values
      .firstWhere((s) => s.value == value, orElse: () => PromoModerationStatus.normale);
}

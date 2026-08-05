import 'api_enum.dart';

/// Miroir de `PromoModerationStatus` (backend) — indépendant du cycle de vie
/// (CLAUDE.md règle #8).
enum PromoModerationStatus {
  normale('normale'),
  signalee('signalee'),
  masquee('masquee'),
  verifieeOk('verifiee_ok');

  const PromoModerationStatus(this.value);

  final String value;

  /// Repli : un statut de modération inconnu est traité comme normal — ne
  /// jamais masquer un contenu à cause d'une valeur qu'on ne comprend pas.
  static PromoModerationStatus fromValue(String value) => fromApiValue(
        valeurs: PromoModerationStatus.values,
        valeurDe: (v) => v.value,
        recu: value,
        repli: PromoModerationStatus.normale,
        enumeration: 'PromoModerationStatus',
      );
}

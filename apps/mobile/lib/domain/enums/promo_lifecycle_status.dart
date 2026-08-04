import 'api_enum.dart';

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

  /// ⚠️ **Le repli le plus lourd du lot** : une promo au statut inconnu
  /// DISPARAÎT de l'affichage client, et le diagnostic partirait chercher une
  /// panne de données. Conservé faute de meilleur défaut — aucun n'est juste —
  /// mais il se signale désormais en développement.
  static PromoLifecycleStatus fromValue(String value) => fromApiValue(
        valeurs: PromoLifecycleStatus.values,
        valeurDe: (v) => v.value,
        recu: value,
        repli: PromoLifecycleStatus.expiree,
        enumeration: 'PromoLifecycleStatus',
      );
}

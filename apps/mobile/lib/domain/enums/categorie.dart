/// Liste fermée des catégories (specs §5.6) — miroir de l'enum backend.
/// Le libellé affiché est localisé (`categorieLabel` dans
/// `features/shared/l10n/enum_labels.dart`), pas porté par l'enum lui-même.
enum Categorie {
  alimentation('alimentation'),
  /// Restaurants, fast-foods, salons de thé — distincte d'[alimentation],
  /// qui reste l'achat de produits à emporter. L'ordre de déclaration est
  /// celui d'affichage (`Categorie.values`), d'où la place juste après.
  restauration('restauration'),
  vetementsTextile('vetements_textile'),
  electromenager('electromenager'),
  beauteHygiene('beaute_hygiene'),
  maisonAmeublement('maison_ameublement'),
  autre('autre');

  const Categorie(this.value);

  final String value;

  static Categorie fromValue(String value) =>
      Categorie.values.firstWhere((c) => c.value == value, orElse: () => Categorie.autre);
}

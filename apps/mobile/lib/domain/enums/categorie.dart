/// Liste fermée des catégories (specs §5.6) — miroir de l'enum backend.
/// Le libellé affiché est localisé (`categorieLabel` dans
/// `features/shared/l10n/enum_labels.dart`), pas porté par l'enum lui-même.
enum Categorie {
  alimentation('alimentation'),
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

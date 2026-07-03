/// Liste fermée des catégories (specs §5.6) — miroir de l'enum backend.
enum Categorie {
  alimentation('alimentation', 'Alimentation'),
  vetementsTextile('vetements_textile', 'Vêtements / Textile'),
  electromenager('electromenager', 'Électroménager'),
  beauteHygiene('beaute_hygiene', 'Beauté / Hygiène'),
  maisonAmeublement('maison_ameublement', 'Maison / Ameublement'),
  autre('autre', 'Autre');

  const Categorie(this.value, this.label);

  final String value;
  final String label;

  static Categorie fromValue(String value) =>
      Categorie.values.firstWhere((c) => c.value == value, orElse: () => Categorie.autre);
}

/** Liste fermée des catégories (specs §5.6) — pas de saisie libre. */
export enum Categorie {
  ALIMENTATION = 'alimentation',
  /**
   * Restaurants, fast-foods, salons de thé (2026-07-30). Placée juste après
   * l'alimentation : l'ordre de déclaration est celui d'affichage côté
   * mobile (`Categorie.values`), et ces deux catégories répondent à la même
   * intention. Distincte d'`ALIMENTATION`, qui reste l'achat de produits à
   * emporter — un client cherchant où manger et un client cherchant des
   * courses ne cherchent pas la même chose.
   */
  RESTAURATION = 'restauration',
  VETEMENTS_TEXTILE = 'vetements_textile',
  ELECTROMENAGER = 'electromenager',
  BEAUTE_HYGIENE = 'beaute_hygiene',
  MAISON_AMEUBLEMENT = 'maison_ameublement',
  AUTRE = 'autre',
}

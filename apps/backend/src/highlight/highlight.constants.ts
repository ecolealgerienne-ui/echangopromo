/**
 * Plafond de diapositives dans le bandeau d'accueil. Aligné sur la taille du
 * classement calculé qui sert de repli (`HIGHLIGHT_FALLBACK_LIMIT`) : au-delà
 * d'une dizaine de vignettes défilables horizontalement, plus personne ne va
 * voir la fin — un plafond bas est une contrainte éditoriale, pas technique.
 */
export const HIGHLIGHT_MAX_SLIDES = 10;

/**
 * Nombre de promos remontées par le classement calculé (« meilleures
 * réductions », le comportement historique du bandeau) quand aucune
 * curation active n'est exploitable.
 */
export const HIGHLIGHT_FALLBACK_LIMIT = 8;

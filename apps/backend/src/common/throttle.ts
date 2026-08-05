/**
 * Limite stricte pour les endpoints non authentifiés ou basés sur un
 * identifiant déclaratif non vérifié (login, inscription commerçant,
 * signalement) — 5 requêtes/minute par IP, plus restrictif que la limite
 * globale par défaut (60/min, voir `ThrottlerModule.forRoot` dans
 * `app.module.ts`).
 */
export const STRICT_THROTTLE = { default: { limit: 5, ttl: 60_000 } };

/**
 * Limite pour les actions sensibles déjà authentifiées (création de
 * ressource par un agent, upload, actions destructrices admin, gestion de
 * promo) — moins stricte que `STRICT_THROTTLE` car un usage légitime peut
 * en émettre plusieurs à la suite (ex. un agent onboardant plusieurs
 * commerces), mais toujours en dessous de la limite globale pour qu'un
 * compte compromis ne puisse pas spammer ces routes (audit V1 §2).
 */
export const SENSITIVE_ACTION_THROTTLE = {
  default: { limit: 20, ttl: 60_000 },
};

/**
 * Lecture publique intrinsèquement bavarde : explorer une carte produit
 * légitimement plusieurs requêtes par minute, là où le reste de l'API en
 * produit une par action. La limite globale (60/min) était atteinte en
 * quelques gestes — retour terrain 2026-07-30, où le client se voyait
 * refuser sa propre carte après quelques dézooms.
 *
 * Reste bornée plutôt qu'illimitée : l'endpoint est non authentifié. Le
 * coût unitaire d'une requête est faible et son résultat plafonné
 * (`MAX_MAP_COMMERCANTS`), ce qui justifie d'être plus permissif ici sans
 * ouvrir la porte à un abus.
 *
 * La vraie économie est côté client : la carte n'émet plus qu'une requête
 * par geste (temporisation) et ne redemande que le terrain qu'elle n'a pas
 * déjà (zone chargée élargie) — sans quoi aucune limite ne suffirait.
 */
export const MAP_THROTTLE = { default: { limit: 180, ttl: 60_000 } };

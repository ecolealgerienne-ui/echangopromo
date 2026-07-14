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
export const SENSITIVE_ACTION_THROTTLE = { default: { limit: 20, ttl: 60_000 } };

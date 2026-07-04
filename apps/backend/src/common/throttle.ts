/**
 * Limite stricte pour les endpoints sensibles (login, OTP, signalement)
 * — 5 requêtes/minute par IP, plus restrictif que la limite globale par
 * défaut (60/min, voir `ThrottlerModule.forRoot` dans `app.module.ts`).
 */
export const STRICT_THROTTLE = { default: { limit: 5, ttl: 60_000 } };

/**
 * Longueur du PIN relevée de 4-6 à 6-12 chiffres (décision produit
 * 2026-07-13, suite à la fermeture de la revendication publique de compte —
 * voir `commercant.service.ts`). Appliqué à toute opération qui **fixe**
 * un PIN (inscription, création par agent, changement, réinitialisation).
 */
export const PIN_SET_PATTERN = /^\d{6,12}$/;
export const PIN_SET_MESSAGE = 'Le code PIN doit contenir 6 à 12 chiffres';

/**
 * La connexion et la vérification de l'ancien PIN (changement) restent
 * permissives sur 4-12 chiffres : un PIN fixé avant ce relèvement (4-6
 * chiffres) doit rester utilisable pour se connecter ou prouver sa
 * possession, sans quoi ce changement casserait silencieusement l'accès
 * des commerçants déjà actifs.
 */
export const PIN_VERIFY_PATTERN = /^\d{4,12}$/;
export const PIN_VERIFY_MESSAGE = 'Le code PIN doit contenir entre 4 et 12 chiffres';

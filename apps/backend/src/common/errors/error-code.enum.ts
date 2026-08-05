/**
 * Code d'erreur stable envoyé au client en plus du `message` français —
 * permet au mobile de mapper vers un texte localisé plutôt que d'afficher
 * le message backend brut (préparation i18n ; une seule langue mappée pour
 * l'instant côté mobile, voir `error_messages_fr.dart`).
 */
export enum ErrorCode {
  // Générique / infrastructure — pas de sémantique métier propre.
  VALIDATION_ERROR = 'VALIDATION_ERROR',
  RATE_LIMITED = 'RATE_LIMITED',
  HTTP_ERROR = 'HTTP_ERROR',
  INTERNAL_ERROR = 'INTERNAL_ERROR',

  // Auth
  AUTH_INVALID_CREDENTIALS = 'AUTH_INVALID_CREDENTIALS',
  AUTH_TOKEN_MISSING = 'AUTH_TOKEN_MISSING',
  AUTH_TOKEN_INVALID = 'AUTH_TOKEN_INVALID',
  AUTH_TOKEN_REVOKED = 'AUTH_TOKEN_REVOKED',
  AUTH_FORBIDDEN_ROLE = 'AUTH_FORBIDDEN_ROLE',

  // Admin
  ADMIN_NOT_FOUND = 'ADMIN_NOT_FOUND',

  // Agent
  AGENT_EMAIL_TAKEN = 'AGENT_EMAIL_TAKEN',
  AGENT_NOT_FOUND = 'AGENT_NOT_FOUND',
  AGENT_COMMUNE_NOT_ASSIGNED_TO_AGENT = 'AGENT_COMMUNE_NOT_ASSIGNED_TO_AGENT',

  // Commune
  COMMUNE_NOT_FOUND = 'COMMUNE_NOT_FOUND',

  // Report
  REPORT_ALREADY_SUBMITTED = 'REPORT_ALREADY_SUBMITTED',

  // Device
  DEVICE_ID_MISSING = 'DEVICE_ID_MISSING',

  // Storage
  STORAGE_INVALID_IMAGE = 'STORAGE_INVALID_IMAGE',
  STORAGE_FILE_TOO_LARGE = 'STORAGE_FILE_TOO_LARGE',
  STORAGE_PURPOSE_NOT_ALLOWED = 'STORAGE_PURPOSE_NOT_ALLOWED',
  STORAGE_KEY_NOT_OWNED = 'STORAGE_KEY_NOT_OWNED',

  // Promo
  PROMO_NOT_FOUND = 'PROMO_NOT_FOUND',
  PROMO_NOT_OWNED_BY_COMMERCANT = 'PROMO_NOT_OWNED_BY_COMMERCANT',
  PROMO_DATE_FIN_NOT_FUTURE = 'PROMO_DATE_FIN_NOT_FUTURE',
  PROMO_DATE_FIN_EXCEEDS_MAX = 'PROMO_DATE_FIN_EXCEEDS_MAX',
  PROMO_ACTIVE_CAP_REACHED = 'PROMO_ACTIVE_CAP_REACHED',
  PROMO_ALREADY_PUBLISHED = 'PROMO_ALREADY_PUBLISHED',
  PROMO_NOT_PUBLISHED = 'PROMO_NOT_PUBLISHED',
  PROMO_PRIX_APRES_NOT_LOWER = 'PROMO_PRIX_APRES_NOT_LOWER',
  PROMO_REPUBLISH_TOO_SOON = 'PROMO_REPUBLISH_TOO_SOON',
  PROMO_DAILY_CREATION_CAP_REACHED = 'PROMO_DAILY_CREATION_CAP_REACHED',

  // Highlight (bandeau « Top promos » curé par l'admin)
  HIGHLIGHT_NOT_FOUND = 'HIGHLIGHT_NOT_FOUND',
  HIGHLIGHT_EMPTY_CONTENT = 'HIGHLIGHT_EMPTY_CONTENT',
  HIGHLIGHT_CAP_REACHED = 'HIGHLIGHT_CAP_REACHED',
  HIGHLIGHT_REORDER_MISMATCH = 'HIGHLIGHT_REORDER_MISMATCH',

  // Commercant
  COMMERCANT_PHONE_TAKEN = 'COMMERCANT_PHONE_TAKEN',
  COMMERCANT_NOT_FOUND = 'COMMERCANT_NOT_FOUND',
  COMMERCANT_OLD_PIN_MISMATCH = 'COMMERCANT_OLD_PIN_MISMATCH',
  COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION = 'COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION',
  COMMERCANT_NOT_IN_AGENT_COMMUNES = 'COMMERCANT_NOT_IN_AGENT_COMMUNES',
  COMMERCANT_TERMS_NOT_ACCEPTED = 'COMMERCANT_TERMS_NOT_ACCEPTED',
  COMMERCANT_REGISTRE_NOT_VALIDATED = 'COMMERCANT_REGISTRE_NOT_VALIDATED',
  COMMERCANT_REGISTRE_KEY_MISMATCH = 'COMMERCANT_REGISTRE_KEY_MISMATCH',
  COMMERCANT_PROFILE_PENDING_REVIEW = 'COMMERCANT_PROFILE_PENDING_REVIEW',
  COMMERCANT_ACCOUNT_INACTIVE = 'COMMERCANT_ACCOUNT_INACTIVE',

  /**
   * Notification introuvable **pour ce destinataire** — soit elle appartient à
   * quelqu'un d'autre, soit la purge de rétention l'a effacée.
   *
   * ⚠️ Les deux cas rendent le MÊME code, délibérément : distinguer « pas la
   * tienne » de « n'existe plus » dirait à un tiers qu'un identifiant est
   * valide. Ce qui compte pour l'appelant légitime est identique dans les deux
   * cas — elle n'est plus là.
   *
   * Trouvé le 2026-08-05 par `test-notifications.sh` : `POST
   * /notifications/:id/read` rendait `201` avec un jeton d'un autre rôle. Le
   * `update` étant cadré par `{id, recipientType, recipientId}`, aucune ligne
   * n'était modifiée — pas d'altération de données, mais un succès annoncé sur
   * un geste sans effet (règle 29).
   */
  NOTIFICATION_NOT_FOUND = 'NOTIFICATION_NOT_FOUND',
}

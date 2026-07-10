/// Mirror of `error_messages_fr.dart` — see that file for the rationale.
/// Every key here must exist in `error_messages_fr.dart` and
/// `error_messages_ar.dart` too (CLAUDE.md rule #26).
const Map<String, String> errorMessagesEn = {
  'AUTH_INVALID_CREDENTIALS': 'Invalid credentials.',
  'AUTH_TOKEN_MISSING': 'You must be logged in to perform this action.',
  'AUTH_TOKEN_INVALID': 'Your session has expired. Please log in again.',
  'AUTH_TOKEN_REVOKED': 'Your session has been revoked. Please log in again.',
  'AUTH_FORBIDDEN_ROLE': 'You do not have permission to perform this action.',

  'ADMIN_NOT_FOUND': 'Administrator not found.',

  'AGENT_EMAIL_TAKEN': 'This email is already used by an agent.',
  'AGENT_NOT_FOUND': 'Agent not found.',
  'AGENT_NO_COMMUNE_ASSIGNED': 'This agent is not assigned to any commune.',
  'AGENT_COMMUNE_NOT_ASSIGNED_TO_AGENT':
      'At least one of these communes is not currently assigned to this agent.',

  'COMMUNE_NOT_FOUND': 'Municipality not found.',

  'REPORT_ALREADY_SUBMITTED': 'You have already reported this promo.',

  'DEVICE_ID_MISSING': 'Missing device identifier. Restart the app.',

  'STORAGE_INVALID_IMAGE': 'The uploaded file is not a valid image. Try again with a photo.',
  'STORAGE_FILE_TOO_LARGE': 'The photo is too large. Try again with another photo.',

  'PROMO_NOT_FOUND': 'Promo not found.',
  'PROMO_NOT_OWNED_BY_COMMERCANT': 'This promo does not belong to this merchant.',
  'PROMO_DATE_FIN_NOT_FUTURE': 'The end date must be in the future.',
  'PROMO_ALREADY_PUBLISHED': 'This promo is already published.',
  'PROMO_NOT_PUBLISHED': 'Only a published promo can be stopped.',
  'PROMO_PRIX_APRES_NOT_LOWER': 'The discounted price must be lower than the original price.',

  'COMMERCANT_PHONE_TAKEN': 'This phone number is already registered.',
  'COMMERCANT_NOT_FOUND': 'Merchant not found.',
  'COMMERCANT_PIN_ALREADY_SET':
      'A PIN is already set for this number — contact an administrator to reset it.',
  'COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION': 'No pending verification request.',
  'COMMERCANT_NOT_IN_AGENT_COMMUNES': 'This merchant is not in any of this agent\'s communes.',

  'RATE_LIMITED': 'Too many attempts. Please try again shortly.',
  'HTTP_ERROR': 'An error occurred.',
  'INTERNAL_ERROR': 'An unexpected error occurred. Please try again later.',

  'NETWORK_ERROR': 'Could not reach the server. Check your connection.',
};

/// Mapping code d'erreur backend (`ErrorCode`, voir
/// `apps/backend/src/common/errors/error-code.enum.ts`) -> texte français.
///
/// Le backend envoie un `code` stable plutôt qu'un message figé, et c'est le
/// mobile qui choisit le texte à afficher selon la langue courante
/// (`errorMessagesByLocale` dans `api_exception.dart`) — voir aussi
/// `error_messages_en.dart`/`error_messages_ar.dart` (CLAUDE.md règle #26 :
/// toute entrée ajoutée ici doit être dupliquée dans les deux autres
/// fichiers dans le même commit).
///
/// Volontairement absents de ce mapping : `VALIDATION_ERROR` (message par
/// champ, dynamique, déjà en français côté backend) et les codes dont le
/// message backend interpole une valeur (`PROMO_DATE_FIN_EXCEEDS_MAX`,
/// `PROMO_ACTIVE_CAP_REACHED`) — un mapping statique leur ferait perdre
/// cette valeur. Pour ces codes, [ApiException.displayMessage] retombe sur
/// le message backend brut.
const Map<String, String> errorMessagesFr = {
  'AUTH_INVALID_CREDENTIALS': 'Identifiants invalides.',
  'AUTH_TOKEN_MISSING': 'Vous devez être connecté pour effectuer cette action.',
  'AUTH_TOKEN_INVALID': 'Votre session a expiré. Reconnectez-vous.',
  'AUTH_TOKEN_REVOKED': 'Votre session a été révoquée. Reconnectez-vous.',
  'AUTH_FORBIDDEN_ROLE': "Vous n'avez pas les droits pour effectuer cette action.",

  'ADMIN_NOT_FOUND': 'Administrateur introuvable.',

  'AGENT_EMAIL_TAKEN': 'Cet email est déjà utilisé par un agent.',
  'AGENT_NOT_FOUND': 'Agent introuvable.',
  'AGENT_NO_COMMUNE_ASSIGNED': "Cet agent n'est rattaché à aucune commune.",
  'AGENT_COMMUNE_NOT_ASSIGNED_TO_AGENT':
      "Au moins une de ces communes n'est pas actuellement assignée à cet agent.",

  'COMMUNE_NOT_FOUND': 'Commune introuvable.',

  'REPORT_ALREADY_SUBMITTED': 'Vous avez déjà signalé cette promotion.',

  'DEVICE_ID_MISSING': "Identifiant d'appareil manquant. Redémarrez l'application.",

  'STORAGE_INVALID_IMAGE': "Le fichier envoyé n'est pas une image valide. Réessayez avec une photo.",
  'STORAGE_FILE_TOO_LARGE': 'La photo est trop volumineuse. Réessayez avec une autre photo.',
  'STORAGE_PURPOSE_NOT_ALLOWED': "Ce type d'upload n'est pas autorisé pour ce compte.",

  'PROMO_NOT_FOUND': 'Promotion introuvable.',
  'PROMO_NOT_OWNED_BY_COMMERCANT': "Cette promotion n'appartient pas à ce commerçant.",
  'PROMO_DATE_FIN_NOT_FUTURE': 'La date de fin doit être dans le futur.',
  'PROMO_ALREADY_PUBLISHED': 'Cette promotion est déjà publiée.',
  'PROMO_NOT_PUBLISHED': 'Seule une promotion publiée peut être arrêtée.',
  'PROMO_PRIX_APRES_NOT_LOWER':
      'Le prix après réduction doit être inférieur au prix avant réduction.',

  'COMMERCANT_PHONE_TAKEN': 'Ce numéro de téléphone est déjà enregistré.',
  'COMMERCANT_NOT_FOUND': 'Commerçant introuvable.',
  'COMMERCANT_PIN_ALREADY_SET':
      'Un PIN est déjà défini pour ce numéro — contactez un administrateur pour le réinitialiser.',
  'COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION': 'Aucune demande de vérification en attente.',
  'COMMERCANT_NOT_IN_AGENT_COMMUNES': "Ce commerçant n'est dans aucune des communes de cet agent.",
  'COMMERCANT_TERMS_NOT_ACCEPTED': "Vous devez accepter les conditions d'utilisation pour créer un compte.",
  'COMMERCANT_REGISTRE_NOT_VALIDATED':
      "Votre registre de commerce doit être validé par un administrateur avant de pouvoir publier des promos.",
  'COMMERCANT_REGISTRE_KEY_MISMATCH': "Ce document n'appartient pas à ce commerçant.",

  'RATE_LIMITED': 'Trop de tentatives. Réessayez dans quelques instants.',
  'HTTP_ERROR': 'Une erreur est survenue.',
  'INTERNAL_ERROR': 'Une erreur inattendue est survenue. Réessayez plus tard.',

  /// Pas un `ErrorCode` backend — utilisé par [ApiException.fromDioError]
  /// quand la requête n'a même pas atteint le serveur (pas de réponse HTTP).
  'NETWORK_ERROR': 'Impossible de contacter le serveur. Vérifiez votre connexion.',
};

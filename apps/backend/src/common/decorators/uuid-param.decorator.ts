import { Param, ParseUUIDPipe } from '@nestjs/common';

/**
 * **Le seul endroit qui dit qu'un paramètre d'identifiant est un UUID.**
 *
 * Tous les `:id`/`:promoId`/`:commercantId` des routes sont des clés
 * primaires UUID (`@PrimaryGeneratedColumn('uuid')`). Sans validation de
 * format à la frontière, une chaîne non-UUID atteignait PostgreSQL, qui
 * lève `invalid input syntax for type uuid` — remontée en `500` au lieu
 * d'un `400` (rapport pentest 2026-08-05 §4.3). Aucune fuite (le filtre
 * d'exceptions reste générique), mais un statut trompeur et du bruit dans
 * la supervision : une erreur d'entrée client déguisée en erreur serveur.
 *
 * `ParseUUIDPipe` lève une `BadRequestException` (400) sans `code` métier ;
 * `AllExceptionsFilter` la ramène alors à `{code: VALIDATION_ERROR}`, comme
 * les autres échecs de validation. Un UUID bien formé mais inexistant passe
 * le pipe et rend son `404 …_NOT_FOUND` habituel — c'est bien le format,
 * et lui seul, qu'on refuse ici.
 */
export const UuidParam = (name: string): ParameterDecorator =>
  Param(name, new ParseUUIDPipe());

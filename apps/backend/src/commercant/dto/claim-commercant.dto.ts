import { IsPhoneNumber, Matches } from 'class-validator';

/**
 * Un commerçant créé par un agent (ou dont le PIN a été réinitialisé par
 * l'admin) définit lui-même son PIN pour activer son compte — aucune preuve
 * de possession du numéro n'est demandée (décision produit : pas d'OTP SMS).
 */
export class ClaimCommercantDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @Matches(/^\d{4,6}$/, { message: 'Le code PIN doit contenir 4 à 6 chiffres' })
  pin: string;
}

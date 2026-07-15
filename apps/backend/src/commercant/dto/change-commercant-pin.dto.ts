import { Matches } from 'class-validator';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN, PIN_VERIFY_MESSAGE, PIN_VERIFY_PATTERN } from '../pin.constants';

/**
 * Le commerçant se souvient encore de son PIN actuel mais veut le changer
 * — libre-service (`PATCH /commercant/me/pin`, décision produit
 * 2026-07-13) : contrairement au flux "PIN oublié", pas besoin de passer
 * par un admin/agent quand on a déjà la preuve de possession du PIN en
 * main. `oldPin` vérifié contre le hash existant côté service avant
 * d'appliquer `newPin` : cette preuve tient lieu de vérification
 * d'identité, sans OTP.
 */
export class ChangeCommercantPinDto {
  @Matches(PIN_VERIFY_PATTERN, { message: PIN_VERIFY_MESSAGE })
  oldPin: string;

  @Matches(PIN_SET_PATTERN, { message: PIN_SET_MESSAGE })
  newPin: string;
}

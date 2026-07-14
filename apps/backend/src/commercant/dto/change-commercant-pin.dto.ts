import { Matches } from 'class-validator';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN, PIN_VERIFY_MESSAGE, PIN_VERIFY_PATTERN } from '../pin.constants';

/**
 * Le commerçant se souvient encore de son PIN actuel mais veut le changer
 * — appelle un admin/agent qui saisit les deux valeurs pendant la
 * conversation (§3.2, pas de flux libre-service commerçant). `oldPin`
 * vérifié contre le hash existant côté service avant d'appliquer `newPin` :
 * la preuve de possession de l'ancien PIN tient lieu de vérification
 * d'identité, sans OTP.
 */
export class ChangeCommercantPinDto {
  @Matches(PIN_VERIFY_PATTERN, { message: PIN_VERIFY_MESSAGE })
  oldPin: string;

  @Matches(PIN_SET_PATTERN, { message: PIN_SET_MESSAGE })
  newPin: string;
}

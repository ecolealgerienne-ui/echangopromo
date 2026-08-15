import { IsISO31661Alpha2, IsOptional, Matches } from 'class-validator';
import { PIN_VERIFY_MESSAGE, PIN_VERIFY_PATTERN } from '../pin.constants';
import { EstTelephoneDuPays } from './telephone-du-pays.validator';

export class LoginCommercantDto {
  @EstTelephoneDuPays()
  telephone: string;

  /**
   * Pays du numéro, ISO 3166-1 alpha-2. Absent ⇒ `DZ` : le pilote est algérien
   * et l'app pré-sélectionne l'Algérie. C'est ce pays qui décide de la forme
   * normalisée et qui entre dans l'unicité `(pays, telephone)` — deux
   * commerçants de pays différents peuvent légitimement porter les mêmes
   * chiffres nationaux.
   */
  @IsOptional()
  @IsISO31661Alpha2()
  pays?: string;

  @Matches(PIN_VERIFY_PATTERN, { message: PIN_VERIFY_MESSAGE })
  pin: string;
}

import {
  IsBoolean,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsISO31661Alpha2,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN } from '../pin.constants';
import {
  ADRESSE_MAX_LENGTH,
  NOM_MAX_LENGTH,
} from '../entities/commercant.entity';
import { EstTelephoneDuPays } from './telephone-du-pays.validator';

export class RegisterCommercantDto {
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

  @IsString()
  @MinLength(2)
  @MaxLength(NOM_MAX_LENGTH)
  nom: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(ADRESSE_MAX_LENGTH)
  adresse?: string;

  @IsEnum(Categorie)
  categorie: Categorie;

  @Matches(PIN_SET_PATTERN, { message: PIN_SET_MESSAGE })
  pin: string;

  /** Clé S3 de la photo du commerce, déjà uploadée (optionnel). */
  @IsOptional()
  @IsString()
  photoKey?: string;

  /** Position GPS capturée sur l'appareil (optionnel, pas de Google Maps payant). */
  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;

  /** Vérifié explicitement `=== true` dans le service (Phase 4, CGU) — pas juste un booléen présent. */
  @IsBoolean()
  acceptedTerms: boolean;
}

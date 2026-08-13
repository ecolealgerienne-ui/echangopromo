import {
  IsBoolean,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsPhoneNumber,
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

export class RegisterCommercantDto {
  @IsPhoneNumber('DZ')
  telephone: string;

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

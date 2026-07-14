import {
  IsBoolean,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsPhoneNumber,
  IsString,
  IsUUID,
  Matches,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN } from '../pin.constants';

export class RegisterCommercantDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @IsString()
  @MinLength(2)
  nom: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
  adresse?: string;

  @IsEnum(Categorie)
  categorie: Categorie;

  @IsUUID()
  communeId: string;

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

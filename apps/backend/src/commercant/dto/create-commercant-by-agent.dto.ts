import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsPhoneNumber,
  IsString,
  IsUUID,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class CreateCommercantByAgentDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @IsString()
  @MinLength(2)
  nom: string;

  @IsString()
  @MinLength(2)
  adresse: string;

  @IsEnum(Categorie)
  categorie: Categorie;

  @IsUUID()
  communeId: string;

  /** Clé S3 de la photo du commerce, déjà uploadée (optionnel). */
  @IsOptional()
  @IsString()
  photoKey?: string;

  /** Position GPS capturée sur l'appareil de l'agent (optionnel). */
  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;
}

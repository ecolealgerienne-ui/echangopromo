import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import {
  ADRESSE_MAX_LENGTH,
  NOM_MAX_LENGTH,
} from '../entities/commercant.entity';

/**
 * Édition du profil commerçant après inscription — téléphone volontairement
 * exclu (identifiant de connexion, pas un champ de profil ordinaire).
 */
export class UpdateCommercantDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(NOM_MAX_LENGTH)
  nom?: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(ADRESSE_MAX_LENGTH)
  adresse?: string;

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;

  @IsOptional()
  @IsString()
  photoKey?: string;

  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;
}

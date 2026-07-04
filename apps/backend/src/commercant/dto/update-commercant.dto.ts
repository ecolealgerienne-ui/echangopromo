import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

/**
 * Édition du profil commerçant après inscription — téléphone volontairement
 * exclu (identifiant de connexion, pas un champ de profil ordinaire).
 */
export class UpdateCommercantDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  nom?: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
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

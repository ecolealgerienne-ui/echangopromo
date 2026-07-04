import {
  IsEnum,
  IsPhoneNumber,
  IsString,
  IsUUID,
  Matches,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class RegisterCommercantDto {
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

  @Matches(/^\d{4,6}$/, { message: 'Le code PIN doit contenir 4 à 6 chiffres' })
  pin: string;
}

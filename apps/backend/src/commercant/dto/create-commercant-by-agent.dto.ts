import {
  IsEnum,
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
}

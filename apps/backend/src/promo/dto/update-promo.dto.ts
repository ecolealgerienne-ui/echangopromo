import {
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class UpdatePromoDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(140)
  description?: string;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  prixAvant?: number;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  prixApres?: number;

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;

  @IsOptional()
  @IsString()
  @MinLength(1)
  photoKey?: string;
}

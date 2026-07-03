import {
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class UpdatePromoDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  produit?: string;

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

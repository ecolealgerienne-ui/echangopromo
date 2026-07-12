import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
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

  /**
   * Remplace l'intégralité du tableau de photos si fourni (le mobile envoie
   * toujours la liste complète résolue, clés inchangées comprises — voir
   * `PromoService.update`) — pas de patch partiel par index.
   */
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(3)
  @IsString({ each: true })
  @MinLength(1, { each: true })
  photoKeys?: string[];
}

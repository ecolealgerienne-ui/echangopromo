import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PRIX_MAX } from '../entities/promo.entity';

export class UpdatePromoDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(140)
  description?: string;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Max(PRIX_MAX)
  prixAvant?: number;

  @IsOptional()
  @IsNumber()
  @IsPositive()
  @Max(PRIX_MAX)
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

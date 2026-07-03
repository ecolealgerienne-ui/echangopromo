import { Type } from 'class-transformer';
import {
  IsDate,
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class CreatePromoDto {
  @IsString()
  @MinLength(2)
  produit: string;

  @IsNumber()
  @IsPositive()
  prixAvant: number;

  @IsNumber()
  @IsPositive()
  prixApres: number;

  @IsEnum(Categorie)
  categorie: Categorie;

  /** Clé de l'objet S3 de la photo, déjà uploadée via URL pré-signée. */
  @IsString()
  @MinLength(1)
  photoKey: string;

  /**
   * Optionnel — si omis, calculée à `+PROMO_DEFAULT_DURATION_DAYS` jours
   * (5 par défaut). Point ouvert §7.6 des specs : ajustabilité non tranchée,
   * on l'autorise par prudence plutôt que de figer 5 jours en dur.
   */
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  dateFin?: Date;
}

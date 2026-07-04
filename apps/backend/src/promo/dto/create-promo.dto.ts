import { Type } from 'class-transformer';
import {
  IsBoolean,
  IsDate,
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class CreatePromoDto {
  @IsString()
  @MinLength(2)
  @MaxLength(140)
  description: string;

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
   * Ignoré si `asDraft` est vrai. Optionnel — si omis, calculée à
   * `+PROMO_DEFAULT_DURATION_DAYS` jours (5 par défaut), plafonnée à
   * `PROMO_MAX_DURATION_DAYS` (7 par défaut).
   */
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  dateFin?: Date;

  /** Enregistre en brouillon (non publiée, non comptée dans le plafond de 5) au lieu de publier immédiatement. */
  @IsOptional()
  @IsBoolean()
  asDraft?: boolean;
}

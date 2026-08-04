import {
  IsBoolean,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

/**
 * Aucun champ n'est requis individuellement, mais une diapositive vide n'a
 * rien à afficher : la règle « au moins une image importée OU une promo
 * ciblée » est vérifiée dans `HighlightService` (elle porte sur la
 * combinaison des champs, pas sur un champ isolé) et renvoie
 * `HIGHLIGHT_EMPTY_CONTENT`.
 */
export class CreateHighlightDto {
  /** Promo ouverte au clic, et source du visuel si aucune image importée. */
  @IsOptional()
  @IsUUID()
  promoId?: string;

  /**
   * Clé S3 déjà uploadée via `POST /storage/upload` avec
   * `purpose=highlight` (admin uniquement).
   */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(255)
  imageKey?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  titre?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  sousTitre?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

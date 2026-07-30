import {
  IsBoolean,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

/**
 * Patch partiel : un champ absent du corps reste inchangé, un champ envoyé à
 * `null` est effacé (retirer l'image importée, retirer la cible). Le service
 * distingue les deux avec `'champ' in dto` — `@IsOptional()` laisse passer
 * `null` sans le confondre avec une absence, ce que ferait un simple
 * `dto.champ === undefined`.
 */
export class UpdateHighlightDto {
  @IsOptional()
  @IsUUID()
  promoId?: string | null;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(255)
  imageKey?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  titre?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  sousTitre?: string | null;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

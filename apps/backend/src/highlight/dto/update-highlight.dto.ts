import {
  IsBoolean,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  MinLength,
} from 'class-validator';

/**
 * Patch partiel. « Effacer un champ » passe par un drapeau explicite
 * (`clearPromo`, `clearImage`), **jamais** par une valeur `null` distinguée
 * d'une absence : `ValidationPipe` transforme le corps en instance de cette
 * classe, et TypeScript (`useDefineForClassFields`, actif dès la cible
 * ES2022) crée une propriété propre valant `undefined` pour **chaque** champ
 * déclaré, envoyé ou non. Un test `'champ' in dto` serait donc toujours vrai
 * — piège déjà rencontré sur `UpdatePromoDto`/`updateProfile` (voir
 * `PromoService.update`). Seul `!== undefined` distingue réellement les deux
 * cas, d'où cette forme.
 *
 * Pour les textes, la chaîne vide vaut effacement : un titre vide et un
 * titre absent n'ont pas à être distingués côté produit.
 */
export class UpdateHighlightDto {
  @IsOptional()
  @IsUUID()
  promoId?: string;

  /** Retire la promo ciblée : la diapositive devient une affiche seule. */
  @IsOptional()
  @IsBoolean()
  clearPromo?: boolean;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(255)
  imageKey?: string;

  /** Retire l'image importée : la photo de la promo reprend sa place. */
  @IsOptional()
  @IsBoolean()
  clearImage?: boolean;

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

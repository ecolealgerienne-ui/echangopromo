import { IsIn, IsOptional } from 'class-validator';

const ALLOWED_PURPOSES = ['promo', 'commercant'] as const;

export class UploadPhotoDto {
  /** Détermine le préfixe de la clé S3 — 'promo' par défaut (compat. existant). */
  @IsOptional()
  @IsIn(ALLOWED_PURPOSES)
  purpose?: (typeof ALLOWED_PURPOSES)[number];
}

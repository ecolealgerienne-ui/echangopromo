import { IsIn, IsOptional } from 'class-validator';

const ALLOWED_CONTENT_TYPES = ['image/jpeg', 'image/png'] as const;
const ALLOWED_PURPOSES = ['promo', 'commercant'] as const;

export class CreatePresignedUploadDto {
  @IsIn(ALLOWED_CONTENT_TYPES)
  contentType: (typeof ALLOWED_CONTENT_TYPES)[number];

  /** Détermine le préfixe de la clé S3 — 'promo' par défaut (compat. existant). */
  @IsOptional()
  @IsIn(ALLOWED_PURPOSES)
  purpose?: (typeof ALLOWED_PURPOSES)[number];
}

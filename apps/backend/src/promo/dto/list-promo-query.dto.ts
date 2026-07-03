import { Transform } from 'class-transformer';
import { IsArray, IsEnum, IsOptional, IsUUID } from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

export class ListPromoQueryDto {
  @IsOptional()
  @IsUUID()
  communeId?: string;

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;

  /** Commerçants favoris (stockage local client, specs §3.1) — affichés en priorité. */
  @IsOptional()
  @IsArray()
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  favoriteIds?: string[];
}

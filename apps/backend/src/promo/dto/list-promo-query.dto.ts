import { Transform } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsEnum, IsOptional, IsUUID } from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';

export class ListPromoQueryDto extends PaginationQueryDto {
  /**
   * Jusqu'à 4 communes (décision produit 2026-07-12, pensée pour les
   * grandes villes comme Alger où les communes sont accolées — une promo
   * dans l'une intéresse un client dans la voisine). Plafond imposé ici,
   * pas seulement côté app : une garde uniquement client se contourne en
   * appelant l'API directement.
   */
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(4)
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  communeIds?: string[];

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

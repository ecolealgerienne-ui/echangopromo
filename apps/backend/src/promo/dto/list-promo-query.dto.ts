import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsEnum,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';

/**
 * Tri de la liste client. `recent` est le défaut historique (favoris
 * d'abord, puis les plus récemment publiées) : ne jamais changer la valeur
 * par défaut, un client existant qui n'envoie pas ce paramètre doit garder
 * exactement le même ordre qu'avant.
 *
 * `discount` alimente le bandeau "Top promos" de l'accueil : trier côté
 * client ne donnerait que les meilleures réductions *de la page chargée*,
 * pas les meilleures tout court.
 */
export enum PromoSortOrder {
  RECENT = 'recent',
  DISCOUNT = 'discount',
}

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

  /**
   * Recherche libre sur la description de la promo et le nom du commerce
   * (barre de recherche de l'accueil). Plafonnée en longueur : une chaîne
   * arbitrairement longue dans un `ILIKE '%…%'` non indexé est un vecteur
   * de charge inutile sur un endpoint public.
   */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  search?: string;

  /**
   * Restreint à un commerce donné — alimente « Autres promos du magasin »
   * sur la fiche promo, sans nouvel endpoint.
   */
  @IsOptional()
  @IsUUID()
  commercantId?: string;

  @IsOptional()
  @IsEnum(PromoSortOrder)
  sort?: PromoSortOrder;
}

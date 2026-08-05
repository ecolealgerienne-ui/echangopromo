import { Transform } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsUUID } from 'class-validator';

/**
 * Communes dont on veut le centre de carte.
 *
 * Mêmes bornes que `ListPromoQueryDto.communeIds` (1 à 4, le plafond de
 * sélection client) — mais **obligatoire** ici, contrairement à la liste : un
 * centre « de toutes les communes » n'aurait aucun sens, alors qu'une liste
 * sans filtre en a un.
 */
export class MapCenterQueryDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(4)
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  communeIds: string[];
}

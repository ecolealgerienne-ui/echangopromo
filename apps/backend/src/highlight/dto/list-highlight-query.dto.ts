import { Transform } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsOptional, IsUUID } from 'class-validator';

/**
 * Les diapositives curées sont **globales** : l'admin met en avant une
 * opération, pas le contenu d'une commune précise, et une sélection
 * éditoriale qui disparaît selon le filtre de commune du client serait
 * incompréhensible côté admin (« je l'ai mise en avant et je ne la vois
 * pas »).
 *
 * `communeIds` ne sert donc qu'au **repli** calculé (meilleures réductions),
 * qui lui doit rester cohérent avec le fil de l'accueil — mêmes contraintes
 * que `ListPromoQueryDto.communeIds`.
 */
export class ListHighlightQueryDto {
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(4)
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  communeIds?: string[];
}

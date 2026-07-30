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
 *
 * Pas de `page`/`limit` ici, exception assumée à la règle CLAUDE.md #15 :
 * la réponse est bornée par construction à `HIGHLIGHT_MAX_SLIDES` (curation)
 * ou `HIGHLIGHT_FALLBACK_LIMIT` (repli), et un bandeau horizontal n'a pas de
 * « page suivante ». Ce plafond ne dépend d'aucun volume de données, il ne
 * grandira donc pas avec l'extension multi-wilaya — contrairement aux
 * listes que cette règle vise.
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

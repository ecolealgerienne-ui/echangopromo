import { Transform } from 'class-transformer';
import {
  IsDefined,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsPositive,
  ValidateIf,
} from 'class-validator';
import { versNombre } from '../../common/transforms/vers-nombre';

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
  /**
   * Point du client, pour cadrer le **repli** calculé (bascule 2026-08-12).
   *
   * ⚠️ Mêmes contraintes que `ListPromoQueryDto`, et pour la même raison : le
   * repli doit rester cohérent avec le fil de l'accueil. Deux cadrages
   * différents pour deux zones de la même page produiraient une vitrine qui
   * annonce ce que la liste juste en dessous ne contient pas.
   *
   * Absent, le serveur applique son point par défaut — la vitrine n'est donc
   * jamais vide faute de configuration, mais elle n'est jamais nationale non
   * plus.
   */
  @ValidateIf(
    (o: ListHighlightQueryDto) =>
      o.latitude !== undefined || o.longitude !== undefined,
  )
  @IsDefined()
  @Transform(versNombre)
  @IsLatitude()
  latitude?: number;

  @ValidateIf(
    (o: ListHighlightQueryDto) =>
      o.latitude !== undefined || o.longitude !== undefined,
  )
  @IsDefined()
  @Transform(versNombre)
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @Transform(versNombre)
  @IsNumber()
  @IsPositive()
  radiusKm?: number;
}

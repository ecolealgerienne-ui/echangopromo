import { ArrayMaxSize, ArrayMinSize, IsArray, IsUUID } from 'class-validator';
import { HIGHLIGHT_MAX_SLIDES } from '../highlight.constants';

/**
 * Réordonnancement en bloc : la liste complète des diapositives dans
 * l'ordre voulu, jamais un déplacement relatif (« monter d'un cran »).
 * L'écran admin est une liste glisser-déposer — envoyer l'ordre final évite
 * toute divergence entre ce que l'admin voit et ce qui est enregistré.
 */
export class ReorderHighlightsDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(HIGHLIGHT_MAX_SLIDES)
  @IsUUID(undefined, { each: true })
  ids: string[];
}

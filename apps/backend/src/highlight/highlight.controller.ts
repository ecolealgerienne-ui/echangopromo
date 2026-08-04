import { Controller, Get, Query } from '@nestjs/common';
import { StorageService } from '../storage/storage.service';
import { ListHighlightQueryDto } from './dto/list-highlight-query.dto';
import { HighlightService, HighlightSlide } from './highlight.service';

/**
 * Bandeau « Top promos » de l'accueil client, public et non authentifié.
 *
 * Une seule forme de réponse quel que soit le mode (curation admin ou
 * classement calculé de repli) : l'app affiche des diapositives, elle n'a
 * pas à savoir laquelle des deux sources a répondu — `curated` le dit
 * seulement à titre indicatif.
 */
@Controller('highlight')
export class HighlightController {
  constructor(
    private readonly highlightService: HighlightService,
    private readonly storageService: StorageService,
  ) {}

  /**
   * DTO de sortie explicite, jamais un spread de l'entité (CLAUDE.md #4) —
   * `imageKey` contient l'UUID de l'admin, un identifiant interne qui n'a
   * rien à faire dans une réponse publique.
   *
   * L'image importée par l'admin prime sur la photo de la promo : c'est
   * exactement la raison d'être du champ (visuel dédié au bandeau, souvent
   * au format paysage, là où la photo produit est cadrée pour la fiche).
   */
  private toClientJson(slide: HighlightSlide) {
    const promo = slide.promo;
    const promoImageUrl = promo
      ? promo.thumbnailKey
        ? this.storageService.buildPublicUrl(promo.thumbnailKey)
        : promo.photoKeys[0]
          ? this.storageService.buildPublicUrl(promo.photoKeys[0])
          : null
      : null;

    return {
      id: slide.id,
      curated: slide.curated,
      titre: slide.titre,
      sousTitre: slide.sousTitre,
      imageUrl: slide.imageKey
        ? this.storageService.buildPublicUrl(slide.imageKey)
        : promoImageUrl,
      promoId: promo?.id ?? null,
      promoDescription: promo?.description ?? null,
      prixAvant: promo?.prixAvant ?? null,
      prixApres: promo?.prixApres ?? null,
      commercantNom: slide.commercant?.nom ?? null,
    };
  }

  @Get()
  async list(@Query() query: ListHighlightQueryDto) {
    const slides = await this.highlightService.findForClient(query.communeIds);
    return { items: slides.map((slide) => this.toClientJson(slide)) };
  }
}

import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Commercant } from '../commercant/entities/commercant.entity';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { Promo } from '../promo/entities/promo.entity';
import { PromoSortOrder } from '../promo/dto/list-promo-query.dto';
import { PromoService } from '../promo/promo.service';
import { StorageService } from '../storage/storage.service';
import { CreateHighlightDto } from './dto/create-highlight.dto';
import { ReorderHighlightsDto } from './dto/reorder-highlights.dto';
import { UpdateHighlightDto } from './dto/update-highlight.dto';
import { Highlight } from './entities/highlight.entity';
import {
  HIGHLIGHT_FALLBACK_LIMIT,
  HIGHLIGHT_MAX_SLIDES,
} from './highlight.constants';

/**
 * Une diapositive prête à afficher, curée ou calculée — le client ne doit
 * pas avoir à connaître les deux modes. `curated: false` identifie le repli
 * calculé (aucune curation active exploitable), utile pour comprendre ce
 * qu'on regarde côté app comme en debug.
 */
export interface HighlightSlide {
  id: string;
  curated: boolean;
  titre: string | null;
  sousTitre: string | null;
  imageKey: string | null;
  promo: Promo | null;
  commercant: Commercant | null;
}

@Injectable()
export class HighlightService {
  private readonly logger = new Logger(HighlightService.name);

  constructor(
    @InjectRepository(Highlight)
    private readonly highlights: Repository<Highlight>,
    private readonly promoService: PromoService,
    private readonly storageService: StorageService,
  ) {}

  // --- Lecture client ---

  /**
   * Bandeau d'accueil : la curation admin si elle donne au moins une
   * diapositive affichable, sinon le classement calculé (« meilleures
   * réductions ») qui était le comportement historique.
   *
   * Ce repli n'est pas une commodité : sans lui, une seule promo curée
   * arrivée à expiration viderait la vitrine de l'accueil jusqu'à ce que
   * l'admin s'en aperçoive.
   */
  async findForClient(communeIds?: string[]): Promise<HighlightSlide[]> {
    // Pas de `relations` ici : la promo affichée est celle que
    // `findVisibleByIds` renvoie (avec son commerçant), charger la relation
    // une seconde fois par la jointure ne servirait à rien.
    const curated = await this.highlights.find({
      where: { active: true },
      order: { position: 'ASC', createdAt: 'ASC' },
      take: HIGHLIGHT_MAX_SLIDES,
    });

    const slides = curated.length > 0 ? await this.keepDisplayable(curated) : [];
    if (slides.length > 0) return slides;

    return this.buildFallbackSlides(communeIds);
  }

  /**
   * Écarte les diapositives devenues inaffichables depuis leur création :
   * promo expirée/masquée/dépubliée, commerce suspendu ou supprimé, ou plus
   * rien à montrer du tout (une promo purgée met `promoId` à NULL, voir
   * l'entité). L'admin, lui, continue de les voir dans sa liste — c'est là
   * qu'elles sont corrigeables.
   *
   * Une seule requête pour toutes les promos ciblées (CLAUDE.md règle #14),
   * jamais une vérification par diapositive.
   */
  private async keepDisplayable(curated: Highlight[]): Promise<HighlightSlide[]> {
    const promoIds = curated
      .map((highlight) => highlight.promoId)
      .filter((id): id is string => id !== null);
    const visiblePromos = await this.promoService.findVisibleByIds(promoIds);
    const visibleById = new Map(visiblePromos.map((promo) => [promo.id, promo]));

    const displayable: HighlightSlide[] = [];
    for (const highlight of curated) {
      // `findVisibleByIds` couvre aussi le commerce (supprimé, suspendu) :
      // une seule règle, celle de `PromoService`, jamais réécrite ici.
      const promo = highlight.promoId
        ? (visibleById.get(highlight.promoId) ?? null)
        : null;
      if (highlight.promoId && !promo) continue;
      // Ni image importée ni promo à illustrer : rien à afficher.
      if (!highlight.imageKey && !promo) continue;

      displayable.push({
        id: highlight.id,
        curated: true,
        titre: highlight.titre,
        sousTitre: highlight.sousTitre,
        imageKey: highlight.imageKey,
        promo,
        commercant: promo?.commercant ?? null,
      });
    }
    return displayable;
  }

  /** Comportement d'avant la curation : les plus fortes réductions. */
  private async buildFallbackSlides(communeIds?: string[]): Promise<HighlightSlide[]> {
    const result = await this.promoService.findActiveForClient({
      page: 1,
      limit: HIGHLIGHT_FALLBACK_LIMIT,
      sort: PromoSortOrder.DISCOUNT,
      ...(communeIds?.length ? { communeIds } : {}),
    });
    return result.items.map((promo) => ({
      // Préfixé : cet identifiant n'est pas celui d'une ligne `highlight`,
      // aucun appel admin ne doit pouvoir être construit à partir de lui.
      id: `auto-${promo.id}`,
      curated: false,
      titre: null,
      sousTitre: null,
      imageKey: null,
      promo,
      commercant: promo.commercant ?? null,
    }));
  }

  // --- Gestion admin ---

  /**
   * Toutes les diapositives, inactives et périmées comprises, chacune
   * accompagnée de `promoVisible` : c'est ce drapeau qui permet à l'écran
   * admin de signaler « cette mise en avant ne s'affiche plus » (promo
   * expirée, masquée, commerce suspendu) au lieu de la présenter comme
   * publiée alors que le client ne la voit pas.
   *
   * Une seule requête de vérification pour toute la liste (CLAUDE.md #14).
   */
  async findAllForAdmin(): Promise<{ highlight: Highlight; promoVisible: boolean }[]> {
    const highlights = await this.highlights.find({
      relations: { promo: { commercant: true } },
      order: { position: 'ASC', createdAt: 'ASC' },
    });
    const visiblePromos = await this.promoService.findVisibleByIds(
      highlights
        .map((highlight) => highlight.promoId)
        .filter((id): id is string => id !== null),
    );
    const visibleIds = new Set(visiblePromos.map((promo) => promo.id));
    return highlights.map((highlight) => ({
      highlight,
      // Une diapositive sans promo ciblée (bandeau image seule) est toujours
      // affichable : rien à invalider.
      promoVisible: highlight.promoId === null || visibleIds.has(highlight.promoId),
    }));
  }

  async findByIdOrFail(id: string): Promise<Highlight> {
    const highlight = await this.highlights.findOne({
      where: { id },
      relations: { promo: { commercant: true } },
    });
    if (!highlight) {
      throw new NotFoundAppException(
        ErrorCode.HIGHLIGHT_NOT_FOUND,
        'Mise en avant introuvable',
      );
    }
    return highlight;
  }

  /**
   * Même drapeau que `findAllForAdmin`, pour une seule diapositive — la
   * réponse à une création/édition doit décrire l'état réel, pas supposer
   * qu'une cible fraîchement choisie est forcément affichable (une promo
   * en brouillon ou expirée peut parfaitement être sélectionnée).
   */
  async findByIdForAdmin(
    id: string,
  ): Promise<{ highlight: Highlight; promoVisible: boolean }> {
    const highlight = await this.findByIdOrFail(id);
    const promoVisible =
      highlight.promoId === null ||
      (await this.promoService.findVisibleByIds([highlight.promoId])).length > 0;
    return { highlight, promoVisible };
  }

  /**
   * Plafond et position calculés **dans la même transaction** que
   * l'insertion, derrière un verrou consultatif — un `count()` suivi d'un
   * `save()` laisserait passer deux créations simultanées au-delà du
   * plafond, et deux diapositives sur la même position (CLAUDE.md #13, même
   * schéma que `PromoService.withCommercantLock` pour le plafond de 5
   * promos). Le compte admin est unique en V0, mais la règle ne dépend pas
   * de cette hypothèse : elle tombera le jour où il y aura deux admins.
   */
  async create(dto: CreateHighlightDto): Promise<Highlight> {
    this.assertHasContent(dto.imageKey ?? null, dto.promoId ?? null);
    // Hors transaction : c'est une lecture sur une autre table, la garder
    // dedans allongerait la section critique sans rien protéger de plus.
    await this.assertPromoExists(dto.promoId ?? null);

    return this.highlights.manager.transaction(async (manager) => {
      await manager.query('SELECT pg_advisory_xact_lock(hashtext($1)::bigint)', [
        'highlight-cap',
      ]);

      const total = await manager.count(Highlight);
      if (total >= HIGHLIGHT_MAX_SLIDES) {
        throw new BadRequestAppException(
          ErrorCode.HIGHLIGHT_CAP_REACHED,
          `Le bandeau d'accueil est limité à ${HIGHLIGHT_MAX_SLIDES} mises en avant. Supprimez-en une pour en ajouter une nouvelle.`,
        );
      }

      // Ajoutée en fin de bandeau : l'admin la remonte ensuite par
      // glisser-déposer s'il le souhaite, plutôt qu'une nouvelle entrée
      // vienne s'imposer en tête de vitrine.
      const highestPosition = await manager
        .createQueryBuilder(Highlight, 'highlight')
        .select('MAX(highlight.position)', 'max')
        .getRawOne<{ max: number | null }>();

      return manager.save(
        manager.create(Highlight, {
          position: (highestPosition?.max ?? 0) + 1,
          active: dto.active ?? true,
          promoId: dto.promoId ?? null,
          imageKey: dto.imageKey ?? null,
          titre: dto.titre?.trim() || null,
          sousTitre: dto.sousTitre?.trim() || null,
        }),
      );
    });
  }

  /**
   * Patch partiel : champ absent = inchangé, drapeau `clear*` = effacé.
   *
   * Uniquement des tests `!== undefined` ici, jamais `'champ' in dto` : le
   * DTO transformé porte une propriété propre `undefined` pour chaque champ
   * déclaré non envoyé (voir `UpdateHighlightDto`), un test d'existence de
   * clé serait donc toujours vrai et effacerait la promo et l'image au
   * moindre PATCH partiel — par exemple la simple bascule visible/masqué
   * depuis la liste admin.
   */
  async update(id: string, dto: UpdateHighlightDto): Promise<Highlight> {
    const highlight = await this.findRowOrFail(id);
    const previousImageKey = highlight.imageKey;

    if (dto.clearPromo === true) {
      highlight.promoId = null;
    } else if (dto.promoId !== undefined) {
      highlight.promoId = dto.promoId;
    }

    if (dto.clearImage === true) {
      highlight.imageKey = null;
    } else if (dto.imageKey !== undefined) {
      highlight.imageKey = dto.imageKey;
    }

    if (dto.titre !== undefined) highlight.titre = dto.titre.trim() || null;
    if (dto.sousTitre !== undefined) {
      highlight.sousTitre = dto.sousTitre.trim() || null;
    }
    if (dto.active !== undefined) highlight.active = dto.active;

    this.assertHasContent(highlight.imageKey, highlight.promoId);
    await this.assertPromoExists(highlight.promoId);

    await this.highlights.save(highlight);

    // L'ancienne image n'est plus référencée par personne (une clé n'est
    // jamais réécrite, `buildKey` génère toujours un UUID neuf) — la laisser
    // sur S3 en ferait un objet orphelin payant et invisible.
    if (previousImageKey && previousImageKey !== highlight.imageKey) {
      await this.deleteImage(previousImageKey);
    }
    return this.findByIdOrFail(id);
  }

  async remove(id: string): Promise<void> {
    const highlight = await this.findRowOrFail(id);
    await this.highlights.delete(id);
    if (highlight.imageKey) await this.deleteImage(highlight.imageKey);
  }

  /**
   * Ligne seule, sans relation chargée — indispensable avant un `save` :
   * une entité dont `promo` est hydraté et dont on modifie ensuite `promoId`
   * laisse TypeORM arbitrer entre les deux (la relation l'emporte), ce qui
   * écraserait la nouvelle cible par l'ancienne. Sans relation chargée,
   * seules les colonnes sont persistées.
   */
  private async findRowOrFail(id: string): Promise<Highlight> {
    const highlight = await this.highlights.findOne({ where: { id } });
    if (!highlight) {
      throw new NotFoundAppException(
        ErrorCode.HIGHLIGHT_NOT_FOUND,
        'Mise en avant introuvable',
      );
    }
    return highlight;
  }

  /**
   * Réordonnancement en bloc dans une transaction : un ordre partiellement
   * appliqué (crash au milieu de la boucle) laisserait des positions
   * dupliquées, donc un bandeau dont l'ordre dépend du hasard du tri
   * secondaire.
   */
  async reorder(
    dto: ReorderHighlightsDto,
  ): Promise<{ highlight: Highlight; promoVisible: boolean }[]> {
    const existing = await this.highlights.find({ select: { id: true } });
    const existingIds = new Set(existing.map((highlight) => highlight.id));
    const submitted = new Set(dto.ids);
    // Exige la liste complète, exactement une fois chacune : un ordre
    // partiel laisserait les absentes sur d'anciennes positions, mélangées
    // aux nouvelles sans que l'admin puisse le prévoir.
    if (
      submitted.size !== dto.ids.length ||
      submitted.size !== existingIds.size ||
      dto.ids.some((id) => !existingIds.has(id))
    ) {
      throw new BadRequestAppException(
        ErrorCode.HIGHLIGHT_REORDER_MISMATCH,
        "L'ordre envoyé ne correspond pas aux mises en avant existantes. Rechargez la liste.",
      );
    }

    await this.highlights.manager.transaction(async (manager) => {
      // Séquentiel, pas `Promise.all` : une transaction TypeORM tient une
      // seule connexion, y lancer des requêtes en parallèle n'est pas
      // supporté. Dix lignes au maximum (`HIGHLIGHT_MAX_SLIDES`), le coût
      // est sans objet.
      for (const [index, id] of dto.ids.entries()) {
        await manager.update(Highlight, { id }, { position: index + 1 });
      }
    });
    return this.findAllForAdmin();
  }

  // --- Gardes ---

  private assertHasContent(imageKey: string | null, promoId: string | null): void {
    if (!imageKey && !promoId) {
      throw new BadRequestAppException(
        ErrorCode.HIGHLIGHT_EMPTY_CONTENT,
        'Une mise en avant doit cibler une promo ou porter une image importée.',
      );
    }
  }

  /**
   * Lève `PROMO_NOT_FOUND` — un id inexistant doit être refusé à la
   * création, pas produire une diapositive silencieusement filtrée à
   * l'affichage que l'admin croirait publiée.
   */
  private async assertPromoExists(promoId: string | null): Promise<void> {
    if (promoId) await this.promoService.findByIdOrFail(promoId);
  }

  /**
   * Best-effort, comme la génération de vignette côté promo : l'objet S3
   * orphelin coûte quelques kilo-octets, échouer la suppression d'une
   * diapositive pour ça coûterait bien plus à l'admin.
   */
  private async deleteImage(key: string): Promise<void> {
    try {
      await this.storageService.deleteObject(key);
    } catch (error) {
      this.logger.warn(`Suppression de l'image de mise en avant ${key} échouée: ${error}`);
    }
  }

}

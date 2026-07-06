import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { EntityManager, In, IsNull, LessThan, Not, Repository } from 'typeorm';
import { CommercantService } from '../commercant/commercant.service';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { PromoView } from './entities/promo-view.entity';
import {
  Promo,
  PromoLifecycleStatus,
  PromoModerationStatus,
  VISIBLE_MODERATION_STATUSES,
} from './entities/promo.entity';

const MAX_PROMOS_ACTIVES = 5;

@Injectable()
export class PromoService {
  private readonly logger = new Logger(PromoService.name);

  constructor(
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
    @InjectRepository(PromoView) private readonly views: Repository<PromoView>,
    private readonly commercantService: CommercantService,
    private readonly storageService: StorageService,
    private readonly configService: ConfigService,
  ) {}

  private defaultDureeJours(): number {
    return this.configService.get<number>('PROMO_DEFAULT_DURATION_DAYS', 5);
  }

  private maxDureeJours(): number {
    return this.configService.get<number>('PROMO_MAX_DURATION_DAYS', 7);
  }

  private imageRetentionDays(): number {
    return this.configService.get<number>('IMAGE_RETENTION_DAYS', 30);
  }

  /** Calcule/valide la date de fin — jamais plus loin que `PROMO_MAX_DURATION_DAYS`. */
  private resolveDateFin(requested?: Date): Date {
    const now = Date.now();
    const max = new Date(now + this.maxDureeJours() * 24 * 60 * 60 * 1000);
    const dateFin =
      requested ?? new Date(now + this.defaultDureeJours() * 24 * 60 * 60 * 1000);

    if (dateFin.getTime() <= now) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DATE_FIN_NOT_FUTURE,
        'La date de fin doit être dans le futur',
      );
    }
    if (dateFin.getTime() > max.getTime()) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DATE_FIN_EXCEEDS_MAX,
        `La date de fin ne peut pas dépasser ${this.maxDureeJours()} jours`,
      );
    }
    return dateFin;
  }

  /**
   * Plafond de 5 promos actives (specs §5.3), compté sur `lifecycleStatus =
   * publiee` uniquement — un brouillon ou une promo arrêtée ne compte pas.
   * Appelé sous verrou consultatif Postgres scopé au commerçant (voir
   * `create`/`publish`) — sans ça, deux publications quasi simultanées
   * peuvent chacune lire un compte de 4 et passer, aboutissant à 6 actives.
   */
  private async assertUnderCap(
    manager: EntityManager,
    commercantId: string,
  ): Promise<void> {
    const activeCount = await manager.count(Promo, {
      where: { commercantId, lifecycleStatus: PromoLifecycleStatus.PUBLIEE },
    });
    if (activeCount >= MAX_PROMOS_ACTIVES) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_ACTIVE_CAP_REACHED,
        `Plafond de ${MAX_PROMOS_ACTIVES} promos actives atteint pour ce commerçant`,
      );
    }
  }

  private async withCommercantLock<T>(
    commercantId: string,
    fn: (manager: EntityManager) => Promise<T>,
  ): Promise<T> {
    return this.promos.manager.transaction(async (manager) => {
      await manager.query(
        'SELECT pg_advisory_xact_lock(hashtext($1)::bigint)',
        [commercantId],
      );
      return fn(manager);
    });
  }

  /**
   * Création (specs §3.2/§5.3) — `asDraft: true` enregistre en brouillon
   * (non visible, non compté dans le plafond, `dateFin` non fixée) ;
   * sinon publie immédiatement (comportement historique, comportement par
   * défaut pour ne rien casser côté agent).
   */
  async create(commercantId: string, dto: CreatePromoDto): Promise<Promo> {
    await this.commercantService.findByIdOrFail(commercantId);
    this.assertPriceOrder(dto.prixAvant, dto.prixApres);

    const base = {
      commercantId,
      description: dto.description,
      prixAvant: dto.prixAvant.toFixed(2),
      prixApres: dto.prixApres.toFixed(2),
      categorie: dto.categorie,
      photoKey: dto.photoKey,
    };

    if (dto.asDraft) {
      return this.promos.save(
        this.promos.create({
          ...base,
          dateFin: null,
          lifecycleStatus: PromoLifecycleStatus.BROUILLON,
        }),
      );
    }

    const dateFin = this.resolveDateFin(dto.dateFin);
    return this.withCommercantLock(commercantId, async (manager) => {
      await this.assertUnderCap(manager, commercantId);
      return manager.save(
        manager.create(Promo, {
          ...base,
          dateFin,
          lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        }),
      );
    });
  }

  /**
   * Publie un brouillon, ou republie une promo arrêtée/expirée — toujours
   * avec une `dateFin` recalculée à neuf (jamais une simple prolongation :
   * specs §3.2, "republication complète requise pour réactiver"). C'est ce
   * geste explicite qui constitue la republication complète, pas une
   * resaisie du formulaire.
   */
  async publish(promoId: string): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    if (promo.lifecycleStatus === PromoLifecycleStatus.PUBLIEE) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_ALREADY_PUBLISHED,
        'Cette promo est déjà publiée',
      );
    }

    const dateFin = this.resolveDateFin();
    return this.withCommercantLock(promo.commercantId, async (manager) => {
      await this.assertUnderCap(manager, promo.commercantId);
      promo.lifecycleStatus = PromoLifecycleStatus.PUBLIEE;
      promo.dateFin = dateFin;
      return manager.save(promo);
    });
  }

  /** Arrêt volontaire par le commerçant (ex. rupture de stock) — libère un slot immédiatement. */
  async stop(promoId: string): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    if (promo.lifecycleStatus !== PromoLifecycleStatus.PUBLIEE) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_NOT_PUBLISHED,
        'Seule une promo publiée peut être arrêtée',
      );
    }
    promo.lifecycleStatus = PromoLifecycleStatus.ARRETEE;
    return this.promos.save(promo);
  }

  /**
   * Liste des promos actives filtrée par commune/catégorie (specs §3.1).
   * Tri par défaut : favoris d'abord, puis expiration la plus proche —
   * proposition non confirmée (point ouvert §7.2), appliquée par défaut en
   * l'absence d'autre arbitrage.
   */
  async findActiveForClient(
    query: ListPromoQueryDto,
  ): Promise<PaginatedResult<Promo>> {
    const qb = this.promos
      .createQueryBuilder('promo')
      .innerJoinAndSelect('promo.commercant', 'commercant')
      .where('promo.lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .andWhere('promo.moderationStatus IN (:...moderationStatuses)', {
        moderationStatuses: VISIBLE_MODERATION_STATUSES,
      })
      .andWhere('promo.dateFin > NOW()');

    if (query.communeId) {
      qb.andWhere('commercant.communeId = :communeId', {
        communeId: query.communeId,
      });
    }
    if (query.categorie) {
      qb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }

    if (query.favoriteIds?.length) {
      qb.addSelect(
        `CASE WHEN promo.commercantId IN (:...favoriteIds) THEN 0 ELSE 1 END`,
        'favorite_rank',
      ).setParameter('favoriteIds', query.favoriteIds);
      qb.orderBy('favorite_rank', 'ASC');
    }
    qb.addOrderBy('promo.dateFin', 'ASC');
    qb.skip((query.page - 1) * query.limit).take(query.limit);

    const [items, total] = await qb.getManyAndCount();
    return toPaginatedResult(items, total, query.page, query.limit);
  }

  async findByIdOrFail(id: string): Promise<Promo> {
    const promo = await this.promos.findOne({
      where: { id },
      relations: { commercant: true },
    });
    if (!promo) {
      throw new NotFoundAppException(ErrorCode.PROMO_NOT_FOUND, 'Promo introuvable');
    }
    return promo;
  }

  /**
   * Une seule requête pour plusieurs ids (ex. file de modération) — jamais
   * `ids.map(id => findByIdOrFail(id))`, qui refait un SELECT par élément
   * (CLAUDE.md règle #14, N+1 réapparu sur ce même écran après le premier
   * correctif V0, cf. audit V1 §5).
   */
  async findByIds(ids: string[]): Promise<Promo[]> {
    if (ids.length === 0) return [];
    return this.promos.find({
      where: { id: In(ids) },
      relations: { commercant: true },
    });
  }

  async listByCommercant(
    commercantId: string,
    page: number,
    limit: number,
  ): Promise<PaginatedResult<Promo>> {
    const [items, total] = await this.promos.findAndCount({
      where: { commercantId },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  async recordView(promoId: string, deviceId: string): Promise<void> {
    await this.views
      .createQueryBuilder()
      .insert()
      .values({ promoId, deviceId })
      .orIgnore()
      .execute();
  }

  async getViewCounts(promoIds: string[]): Promise<Record<string, number>> {
    if (promoIds.length === 0) return {};
    const rows = await this.views
      .createQueryBuilder('view')
      .select('view.promoId', 'promoId')
      .addSelect('COUNT(*)', 'count')
      .where('view.promoId IN (:...promoIds)', { promoIds })
      .groupBy('view.promoId')
      .getRawMany<{ promoId: string; count: string }>();

    return Object.fromEntries(
      rows.map((row) => [row.promoId, Number(row.count)]),
    );
  }

  /** Tâche planifiée quotidienne (specs §5.1) — bascule automatique à expiration. */
  @Cron(CronExpression.EVERY_DAY_AT_1AM)
  async expireOutdatedPromosCron(): Promise<void> {
    const count = await this.expireOutdatedPromos();
    this.logger.log(`${count} promo(s) passée(s) en statut expirée`);
  }

  async expireOutdatedPromos(): Promise<number> {
    const result = await this.promos
      .createQueryBuilder()
      .update(Promo)
      .set({ lifecycleStatus: PromoLifecycleStatus.EXPIREE })
      .where('dateFin < NOW()')
      .andWhere('lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .execute();
    return result.affected ?? 0;
  }

  async markSignalee(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId, moderationStatus: Not(PromoModerationStatus.MASQUEE) },
      { moderationStatus: PromoModerationStatus.SIGNALEE },
    );
  }

  /** Décision admin : masquer une promo signalée à tort ou réellement abusive (specs §3.4). */
  async resolveMasquer(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId },
      { moderationStatus: PromoModerationStatus.MASQUEE },
    );
  }

  /** Décision admin : promo légitime — ouvre la fenêtre d'ignore de 30 jours (specs §5.4). */
  async resolveVerifieOk(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId },
      { moderationStatus: PromoModerationStatus.VERIFIEE_OK, verifiedOkAt: new Date() },
    );
  }

  /** Décision admin : avertir le commerçant sans changer la visibilité de la promo. */
  async resolveAvertir(promoId: string): Promise<void> {
    const promo = await this.findByIdOrFail(promoId);
    if (promo.moderationStatus === PromoModerationStatus.SIGNALEE) {
      await this.promos.update(
        { id: promoId },
        { moderationStatus: PromoModerationStatus.NORMALE },
      );
    }
  }

  /**
   * Édition du contenu — autorisée quel que soit le cycle de vie (brouillon,
   * publiée, arrêtée, expirée) : c'est l'action de publication/republication
   * qui constitue le "geste actif" des specs, pas une restriction sur
   * l'édition elle-même.
   */
  async update(promoId: string, dto: UpdatePromoDto): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    const prixAvant = dto.prixAvant ?? Number(promo.prixAvant);
    const prixApres = dto.prixApres ?? Number(promo.prixApres);
    this.assertPriceOrder(prixAvant, prixApres);

    Object.assign(promo, {
      ...dto,
      prixAvant: dto.prixAvant?.toFixed(2) ?? promo.prixAvant,
      prixApres: dto.prixApres?.toFixed(2) ?? promo.prixApres,
    });
    return this.promos.save(promo);
  }

  /** Une promo est censée être une réduction — le prix après doit être strictement inférieur. */
  private assertPriceOrder(prixAvant: number, prixApres: number): void {
    if (prixApres >= prixAvant) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_PRIX_APRES_NOT_LOWER,
        'Le prix après réduction doit être inférieur au prix avant réduction',
      );
    }
  }

  /**
   * Tâche planifiée indépendante du cron d'expiration fonctionnelle (specs
   * §5.8) : supprime le fichier S3 des promos de plus d'un mois, mais
   * conserve les métadonnées en base indéfiniment (historique dashboard).
   */
  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async purgeOldPhotosCron(): Promise<void> {
    const cutoff = new Date(
      Date.now() - this.imageRetentionDays() * 24 * 60 * 60 * 1000,
    );
    const eligible = await this.promos.find({
      where: { photoPurgedAt: IsNull(), createdAt: LessThan(cutoff) },
    });

    for (const promo of eligible) {
      await this.storageService.deleteObject(promo.photoKey);
      promo.photoPurgedAt = new Date();
      await this.promos.save(promo);
    }

    this.logger.log(
      `${eligible.length} photo(s) de promo purgée(s) du stockage S3`,
    );
  }

  /**
   * Utilisé par le dashboard admin. Filtre aussi sur `dateFin` comme
   * `findActiveForClient` — sans ça, une promo expirée reste comptée comme
   * "publiée" jusqu'au passage du cron quotidien (`expireOutdatedPromosCron`),
   * jusqu'à 24h de statistique fausse.
   */
  async countVisible(): Promise<number> {
    return this.promos
      .createQueryBuilder('promo')
      .where('promo.lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .andWhere('promo.moderationStatus IN (:...moderationStatuses)', {
        moderationStatuses: VISIBLE_MODERATION_STATUSES,
      })
      .andWhere('promo.dateFin > NOW()')
      .getCount();
  }
}

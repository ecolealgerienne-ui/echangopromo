import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Between, EntityManager, In, IsNull, LessThan, Not, Repository } from 'typeorm';
import { CommercantService } from '../commercant/commercant.service';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import {
  NotificationRecipientType,
  NotificationType,
} from '../notification/entities/notification.entity';
import { NotificationService } from '../notification/notification.service';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoAdminQueryDto } from './dto/list-promo-admin-query.dto';
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
    private readonly notificationService: NotificationService,
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
    const commercant = await this.commercantService.findByIdOrFail(commercantId);
    this.commercantService.assertRegistreValidated(commercant);
    this.commercantService.assertProfileValidated(commercant);
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
    const commercant = await this.commercantService.findByIdOrFail(promo.commercantId);
    this.commercantService.assertRegistreValidated(commercant);
    this.commercantService.assertProfileValidated(commercant);

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
      .andWhere('promo.dateFin > NOW()')
      // Compte commerçant supprimé (soft delete) : ses promos ne doivent
      // plus apparaître aux clients, sans avoir à muter chaque promo.
      .andWhere('commercant.deletedAt IS NULL');

    if (query.communeIds?.length) {
      qb.andWhere('commercant.communeId IN (:...communeIds)', {
        communeIds: query.communeIds,
      });
    }
    if (query.categorie) {
      qb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }

    if (query.favoriteIds?.length) {
      // Favori par promo (id de la promo elle-même), pas par commerçant —
      // décision produit du 2026-07-12 confirmant ce comportement après une
      // régression : une session précédente avait aligné ceci sur
      // commercantId en lisant "Favoris commerçant" dans les specs §3.1,
      // qui reste à corriger dans le même sens.
      qb.addSelect(
        `CASE WHEN promo.id IN (:...favoriteIds) THEN 0 ELSE 1 END`,
        'favorite_rank',
      ).setParameter('favoriteIds', query.favoriteIds);
      qb.orderBy('favorite_rank', 'ASC');
    }
    qb.addOrderBy('promo.dateFin', 'ASC');
    qb.skip((query.page - 1) * query.limit).take(query.limit);

    const [items, total] = await qb.getManyAndCount();
    return toPaginatedResult(items, total, query.page, query.limit);
  }

  /**
   * Vue admin/agent (plan de correction, Phase 2) : toutes les promos, tous
   * statuts confondus (contrairement à `findActiveForClient`) — permet de
   * repérer et masquer un contenu problématique sans attendre 3
   * signalements. `scopedCommuneIds` restreint aux communes d'un agent ;
   * `undefined` = vue globale (admin).
   */
  async findAllForAdmin(
    query: ListPromoAdminQueryDto,
    scopedCommuneIds?: string[],
  ): Promise<PaginatedResult<Promo>> {
    if (scopedCommuneIds && scopedCommuneIds.length === 0) {
      return toPaginatedResult([], 0, query.page, query.limit);
    }

    const qb = this.promos
      .createQueryBuilder('promo')
      .innerJoinAndSelect('promo.commercant', 'commercant')
      .orderBy('promo.createdAt', 'DESC');

    if (query.search) {
      qb.andWhere(
        '(promo.description ILIKE :search OR commercant.nom ILIKE :search)',
        { search: `%${query.search}%` },
      );
    }
    if (query.communeId) {
      qb.andWhere('commercant.communeId = :communeId', { communeId: query.communeId });
    }
    if (query.categorie) {
      qb.andWhere('promo.categorie = :categorie', { categorie: query.categorie });
    }
    if (query.lifecycleStatus) {
      qb.andWhere('promo.lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: query.lifecycleStatus,
      });
    }
    if (query.moderationStatus) {
      qb.andWhere('promo.moderationStatus = :moderationStatus', {
        moderationStatus: query.moderationStatus,
      });
    }
    if (scopedCommuneIds) {
      qb.andWhere('commercant.communeId IN (:...scopedCommuneIds)', { scopedCommuneIds });
    }
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

  /**
   * Relance avant expiration (plan de correction, Phase 6) — jusqu'ici rien
   * ne notifiait le commerçant qu'une promo allait bientôt expirer, tout
   * reposait sur lui pour penser à republier. Fenêtre de 24h alignée sur la
   * cadence quotidienne du cron : chaque promo ne peut croiser cette
   * fenêtre qu'une seule fois (pas de doublon, pas de promo manquée).
   */
  @Cron(CronExpression.EVERY_DAY_AT_9AM)
  async notifyExpiringSoonCron(): Promise<void> {
    // `moderationStatus IN VISIBLE_MODERATION_STATUSES` : une promo masquée
    // par un admin reste `lifecycleStatus = PUBLIEE` en interne (masquer ne
    // touche que moderationStatus) — sans ce filtre, on inviterait le
    // commerçant à "republier" un contenu que l'admin vient justement de
    // retirer pour abus, message contradictoire avec la modération.
    const expiring = await this.promos.find({
      where: {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        moderationStatus: In(VISIBLE_MODERATION_STATUSES),
        dateFin: Between(new Date(), new Date(Date.now() + 24 * 60 * 60 * 1000)),
      },
    });

    for (const promo of expiring) {
      await this.notificationService.create(
        NotificationType.PROMO_EXPIRING_SOON,
        NotificationRecipientType.COMMERCANT,
        promo.commercantId,
        `Votre promo « ${promo.description} » expire bientôt. Pensez à la republier.`,
        promo.id,
      );
    }
    this.logger.log(`${expiring.length} promo(s) notifiée(s) avant expiration`);
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

  /**
   * Décision admin : avertir le commerçant — repasse la promo en brouillon
   * (donc invisible côté client, `dateFin` remise à null comme tout
   * brouillon) le temps que le commerçant la vérifie et la republie
   * explicitement via `publish` (pas de republication automatique).
   */
  async resolveAvertir(promoId: string): Promise<void> {
    const promo = await this.findByIdOrFail(promoId);
    await this.promos.update(
      { id: promoId },
      {
        ...(promo.moderationStatus === PromoModerationStatus.SIGNALEE
          ? { moderationStatus: PromoModerationStatus.NORMALE }
          : {}),
        lifecycleStatus: PromoLifecycleStatus.BROUILLON,
        dateFin: null,
      },
    );
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
    const previousPhotoKey = promo.photoKey;

    // `dto` (transformé par `ValidationPipe`) porte une propriété propre
    // `undefined` pour chaque champ optionnel non fourni (comportement
    // TypeScript `useDefineForClassFields`) — un `{...dto}` direct
    // écraserait donc les champs non envoyés (ex. `description`/`categorie`
    // lors d'un simple changement de photo) avec `undefined`. TypeORM
    // ignore ces `undefined` dans l'UPDATE SQL (la base reste correcte),
    // mais pas l'objet renvoyé au client — même bug que
    // `CommercantService.updateProfile`, trouvé le 2026-07-12 sur ce
    // même cas de figure côté commerçant.
    const definedFields = Object.fromEntries(
      Object.entries(dto).filter(([, value]) => value !== undefined),
    );
    Object.assign(promo, {
      ...definedFields,
      prixAvant: dto.prixAvant?.toFixed(2) ?? promo.prixAvant,
      prixApres: dto.prixApres?.toFixed(2) ?? promo.prixApres,
    });
    const saved = await this.promos.save(promo);
    // Remplacement de photo : l'ancienne devient orpheline dans S3 si on ne
    // la supprime pas explicitement (buildKey génère toujours une nouvelle
    // clé UUID, jamais un remplacement en place).
    if (dto.photoKey && previousPhotoKey && dto.photoKey !== previousPhotoKey) {
      await this.storageService.deleteObject(previousPhotoKey);
    }
    return saved;
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

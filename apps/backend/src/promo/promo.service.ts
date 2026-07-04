import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, LessThan, Not, Repository } from 'typeorm';
import { CommercantService } from '../commercant/commercant.service';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { PromoView } from './entities/promo-view.entity';
import {
  Promo,
  PromoStatus,
  VISIBLE_PROMO_STATUSES,
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

  private imageRetentionDays(): number {
    return this.configService.get<number>('IMAGE_RETENTION_DAYS', 30);
  }

  /**
   * Plafond de 5 promos actives (specs §5.3). Aucune autre condition sur le
   * cycle de vie du compte : les niveaux `auto_inscrit` et `confirme_agent`
   * suffisent tous deux pour publier (specs §3.2), y compris avant
   * revendication — c'est ce qui permet à l'agent de créer la première
   * promo pendant sa visite, avant que le commerçant n'ait défini son PIN.
   *
   * Le compte des promos actives puis l'insertion sont protégés par un
   * verrou consultatif Postgres scopé au commerçant (`pg_advisory_xact_lock`)
   * — sans ça, deux créations quasi simultanées peuvent chacune lire un
   * compte de 4 et passer, aboutissant à 6 promos actives.
   */
  async create(commercantId: string, dto: CreatePromoDto): Promise<Promo> {
    await this.commercantService.findByIdOrFail(commercantId);
    this.assertPriceOrder(dto.prixAvant, dto.prixApres);

    const dateFin =
      dto.dateFin ??
      new Date(Date.now() + this.defaultDureeJours() * 24 * 60 * 60 * 1000);

    return this.promos.manager.transaction(async (manager) => {
      await manager.query(
        'SELECT pg_advisory_xact_lock(hashtext($1)::bigint)',
        [commercantId],
      );

      const activeCount = await manager.count(Promo, {
        where: { commercantId, status: PromoStatus.ACTIVE },
      });
      if (activeCount >= MAX_PROMOS_ACTIVES) {
        throw new BadRequestException(
          `Plafond de ${MAX_PROMOS_ACTIVES} promos actives atteint pour ce commerçant`,
        );
      }

      return manager.save(
        manager.create(Promo, {
          commercantId,
          description: dto.description,
          prixAvant: dto.prixAvant.toFixed(2),
          prixApres: dto.prixApres.toFixed(2),
          categorie: dto.categorie,
          photoKey: dto.photoKey,
          dateFin,
          status: PromoStatus.ACTIVE,
        }),
      );
    });
  }

  /**
   * Liste des promos actives filtrée par commune/catégorie (specs §3.1).
   * Tri par défaut : favoris d'abord, puis expiration la plus proche —
   * proposition non confirmée (point ouvert §7.2), appliquée par défaut en
   * l'absence d'autre arbitrage.
   */
  async findActiveForClient(query: ListPromoQueryDto): Promise<Promo[]> {
    const qb = this.promos
      .createQueryBuilder('promo')
      .innerJoin('promo.commercant', 'commercant')
      .where('promo.status IN (:...statuses)', {
        statuses: VISIBLE_PROMO_STATUSES,
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

    return qb.getMany();
  }

  async findByIdOrFail(id: string): Promise<Promo> {
    const promo = await this.promos.findOne({ where: { id } });
    if (!promo) {
      throw new NotFoundException('Promo introuvable');
    }
    return promo;
  }

  async listByCommercant(commercantId: string): Promise<Promo[]> {
    return this.promos.find({
      where: { commercantId },
      order: { createdAt: 'DESC' },
    });
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
      .set({ status: PromoStatus.EXPIREE })
      .where('dateFin < NOW()')
      .andWhere('status NOT IN (:...terminal)', {
        terminal: [PromoStatus.EXPIREE, PromoStatus.MASQUEE],
      })
      .execute();
    return result.affected ?? 0;
  }

  async markSignalee(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId, status: Not(PromoStatus.MASQUEE) },
      { status: PromoStatus.SIGNALEE },
    );
  }

  /** Décision admin : masquer une promo signalée à tort ou réellement abusive (specs §3.4). */
  async resolveMasquer(promoId: string): Promise<void> {
    await this.promos.update({ id: promoId }, { status: PromoStatus.MASQUEE });
  }

  /** Décision admin : promo légitime — ouvre la fenêtre d'ignore de 30 jours (specs §5.4). */
  async resolveVerifieOk(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId },
      { status: PromoStatus.VERIFIEE_OK, verifiedOkAt: new Date() },
    );
  }

  /** Décision admin : avertir le commerçant sans changer la visibilité de la promo. */
  async resolveAvertir(promoId: string): Promise<void> {
    const promo = await this.findByIdOrFail(promoId);
    if (promo.status === PromoStatus.SIGNALEE) {
      await this.promos.update({ id: promoId }, { status: PromoStatus.ACTIVE });
    }
  }

  /** Mise à jour d'une promo existante par l'agent lors d'une visite (specs §3.3). */
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
      throw new BadRequestException(
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
      .where('promo.status IN (:...statuses)', {
        statuses: VISIBLE_PROMO_STATUSES,
      })
      .andWhere('promo.dateFin > NOW()')
      .getCount();
  }
}

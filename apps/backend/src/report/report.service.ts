import { ConflictException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Promo } from '../promo/entities/promo.entity';
import { PromoService } from '../promo/promo.service';
import { Report } from './entities/report.entity';

const MODERATION_THRESHOLD = 3;
const IGNORE_WINDOW_DAYS = 30;

@Injectable()
export class ReportService {
  constructor(
    @InjectRepository(Report) private readonly reports: Repository<Report>,
    // Accès direct à l'entité Promo (pas au PromoModule) pour la requête
    // agrégée de `listPendingModeration` — évite un import de module en
    // plus juste pour un JOIN en lecture seule (même pattern que
    // CommercantModule pour la même raison, voir commercant.module.ts).
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
    private readonly promoService: PromoService,
  ) {}

  /** 1 signalement par device par promo, seuil de 3 devices distincts (specs §5.4). */
  async createReport(promoId: string, deviceId: string): Promise<void> {
    await this.promoService.findByIdOrFail(promoId);

    const already = await this.reports.findOne({
      where: { promoId, deviceId },
    });
    if (already) {
      throw new ConflictException(
        'Ce signalement a déjà été enregistré pour cet appareil',
      );
    }

    await this.reports.save(this.reports.create({ promoId, deviceId }));

    const activeCount = await this.countActiveReports(promoId);
    if (activeCount >= MODERATION_THRESHOLD) {
      await this.promoService.markSignalee(promoId);
    }
  }

  /**
   * Compte les devices distincts dont le signalement est "actif", c'est à
   * dire non couvert par la fenêtre d'ignore de 30 jours qui suit une
   * validation admin `vérifiée_ok` (specs §5.4). Une fois la fenêtre
   * expirée, les anciens signalements recomptent automatiquement — pas
   * besoin que les devices re-signalent.
   */
  async countActiveReports(promoId: string): Promise<number> {
    const promo = await this.promoService.findByIdOrFail(promoId);

    const qb = this.reports
      .createQueryBuilder('report')
      .select('COUNT(DISTINCT report.deviceId)', 'count')
      .where('report.promoId = :promoId', { promoId });

    if (promo.verifiedOkAt) {
      const windowEnd = new Date(
        promo.verifiedOkAt.getTime() + IGNORE_WINDOW_DAYS * 24 * 60 * 60 * 1000,
      );
      if (windowEnd > new Date()) {
        qb.andWhere('report.createdAt > :verifiedOkAt', {
          verifiedOkAt: promo.verifiedOkAt,
        });
      }
    }

    const raw = await qb.getRawOne<{ count: string }>();
    return Number(raw?.count ?? 0);
  }

  /**
   * File de modération pour l'admin (specs §3.4). Une seule requête
   * agrégée (JOIN + GROUP BY + HAVING) plutôt qu'un `countActiveReports`
   * par promo signalée — l'ancienne version faisait 2 requêtes par promo
   * (fetch + count), non borné par une zone, potentiellement des centaines
   * de requêtes à l'échelle multi-wilaya. La fenêtre d'ignore de 30 jours
   * est répliquée ici en SQL (même seuil, même logique que
   * `countActiveReports`, appliquée par-signalement plutôt qu'après coup).
   */
  async listPendingModeration(): Promise<
    { promoId: string; activeReportCount: number }[]
  > {
    const rows = await this.reports
      .createQueryBuilder('report')
      .innerJoin(Promo, 'promo', 'promo.id = report.promoId')
      .select('report.promoId', 'promoId')
      .addSelect('COUNT(DISTINCT report.deviceId)', 'count')
      .where(
        `(promo.verifiedOkAt IS NULL
          OR report.createdAt > promo.verifiedOkAt
          OR NOW() > promo.verifiedOkAt + make_interval(days => :ignoreWindowDays))`,
        { ignoreWindowDays: IGNORE_WINDOW_DAYS },
      )
      .groupBy('report.promoId')
      .having('COUNT(DISTINCT report.deviceId) >= :threshold', {
        threshold: MODERATION_THRESHOLD,
      })
      .getRawMany<{ promoId: string; count: string }>();

    return rows.map((row) => ({
      promoId: row.promoId,
      activeReportCount: Number(row.count),
    }));
  }
}

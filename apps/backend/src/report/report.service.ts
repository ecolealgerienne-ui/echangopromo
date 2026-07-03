import { ConflictException, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PromoService } from '../promo/promo.service';
import { Report } from './entities/report.entity';

const MODERATION_THRESHOLD = 3;
const IGNORE_WINDOW_DAYS = 30;

@Injectable()
export class ReportService {
  constructor(
    @InjectRepository(Report) private readonly reports: Repository<Report>,
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
   * File de modération pour l'admin (specs §3.4). Réutilise
   * `countActiveReports` (qui applique la fenêtre d'ignore de 30 jours)
   * plutôt qu'un COUNT SQL brut, pour rester cohérent avec le seuil
   * réellement utilisé à la création d'un signalement.
   */
  async listPendingModeration(): Promise<
    { promoId: string; activeReportCount: number }[]
  > {
    const { promoIds } = await this.reports
      .createQueryBuilder('report')
      .select('ARRAY_AGG(DISTINCT report.promoId)', 'promoIds')
      .getRawOne<{ promoIds: string[] | null }>()
      .then((row) => ({ promoIds: row?.promoIds ?? [] }));

    const counts = await Promise.all(
      promoIds.map(async (promoId) => ({
        promoId,
        activeReportCount: await this.countActiveReports(promoId),
      })),
    );

    return counts.filter(
      (entry) => entry.activeReportCount >= MODERATION_THRESHOLD,
    );
  }
}

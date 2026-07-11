import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder } from 'typeorm';
import { Commercant } from '../commercant/entities/commercant.entity';
import { ConflictAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import { Promo, PromoModerationStatus } from '../promo/entities/promo.entity';
import { PromoService } from '../promo/promo.service';
import { Report, ReportReason } from './entities/report.entity';

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
  async createReport(promoId: string, deviceId: string, reason: ReportReason): Promise<void> {
    await this.promoService.findByIdOrFail(promoId);

    const already = await this.reports.findOne({
      where: { promoId, deviceId },
    });
    if (already) {
      throw new ConflictAppException(
        ErrorCode.REPORT_ALREADY_SUBMITTED,
        'Ce signalement a déjà été enregistré pour cet appareil',
      );
    }

    await this.reports.save(this.reports.create({ promoId, deviceId, reason }));

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
        qb.andWhere('"report"."createdAt" > :verifiedOkAt', {
          verifiedOkAt: promo.verifiedOkAt,
        });
      }
    }

    const raw = await qb.getRawOne<{ count: string }>();
    return Number(raw?.count ?? 0);
  }

  /**
   * Base de la requête agrégée (JOIN + GROUP BY + HAVING) partagée entre
   * `listPendingModeration` (page de résultats) et `countPendingModeration`
   * (compteur dashboard) — une seule requête plutôt qu'un
   * `countActiveReports` par promo signalée : l'ancienne version faisait 2
   * requêtes par promo (fetch + count), non borné par une zone,
   * potentiellement des centaines de requêtes à l'échelle multi-wilaya. La
   * fenêtre d'ignore de 30 jours est répliquée ici en SQL (même seuil,
   * même logique que `countActiveReports`, appliquée par-signalement
   * plutôt qu'après coup).
   *
   * `communeIds` restreint la file aux communes d'un agent (plan de
   * correction, Phase 2 : agent = modérateur) — `undefined` = vue globale
   * (admin). Jointure supplémentaire vers `Commercant` seulement dans ce cas,
   * pour ne pas alourdir la requête admin la plus fréquente.
   *
   * `moderationStatus = SIGNALEE` explicite (bug trouvé en relecture,
   * Phase 2/5) : sans ce filtre, une promo déjà résolue (masquée, avertie,
   * vérifiée OK) restait indéfiniment dans la file, ses signalements
   * continuant à compter au-dessus du seuil pour toujours (`verifiedOkAt`
   * n'étant jamais posé par `resolveMasquer`/`resolveAvertir`) — la file ne
   * désenflait jamais après une décision, cassant tout le workflow agent
   * introduit en Phase 2.
   */
  private pendingModerationQueryBuilder(communeIds?: string[]): SelectQueryBuilder<Report> {
    const qb = this.reports
      .createQueryBuilder('report')
      .innerJoin(Promo, 'promo', 'promo.id = report.promoId')
      .select('report.promoId', 'promoId')
      .addSelect('COUNT(DISTINCT report.deviceId)', 'count')
      .where('promo.moderationStatus = :signalee', {
        signalee: PromoModerationStatus.SIGNALEE,
      })
      .andWhere(
        // Identifiants explicitement quotés : TypeORM ne ré-échappe de façon
        // fiable qu'une des occurrences de `promo.verifiedOkAt` dans une
        // chaîne where() brute contenant plusieurs répétitions du même
        // alias.colonne — les autres restent non quotées et Postgres les
        // met en minuscules (`verifiedokat`), colonne inexistante.
        `("promo"."verifiedOkAt" IS NULL
          OR "report"."createdAt" > "promo"."verifiedOkAt"
          OR NOW() > "promo"."verifiedOkAt" + make_interval(days => :ignoreWindowDays))`,
        { ignoreWindowDays: IGNORE_WINDOW_DAYS },
      )
      .groupBy('report.promoId')
      .having('COUNT(DISTINCT report.deviceId) >= :threshold', {
        threshold: MODERATION_THRESHOLD,
      });

    if (communeIds) {
      qb.innerJoin(Commercant, 'commercant', 'commercant.id = promo.commercantId').andWhere(
        'commercant.communeId IN (:...communeIds)',
        { communeIds },
      );
    }
    return qb;
  }

  /** File de modération pour l'admin/agent (specs §3.4), paginée. */
  async listPendingModeration(
    page: number,
    limit: number,
    communeIds?: string[],
  ): Promise<PaginatedResult<{ promoId: string; activeReportCount: number }>> {
    if (communeIds && communeIds.length === 0) {
      return toPaginatedResult([], 0, page, limit);
    }

    const total = await this.countPendingModeration(communeIds);
    const rows = await this.pendingModerationQueryBuilder(communeIds)
      .orderBy('report.promoId', 'ASC')
      .offset((page - 1) * limit)
      .limit(limit)
      .getRawMany<{ promoId: string; count: string }>();

    const items = rows.map((row) => ({
      promoId: row.promoId,
      activeReportCount: Number(row.count),
    }));
    return toPaginatedResult(items, total, page, limit);
  }

  /** Nombre total de promos en attente de modération (stat dashboard, pas de pagination). */
  async countPendingModeration(communeIds?: string[]): Promise<number> {
    if (communeIds && communeIds.length === 0) return 0;
    return this.pendingModerationQueryBuilder(communeIds).getCount();
  }

  /**
   * Répartition des motifs de signalement actifs, pour toute une page de
   * promos en une seule requête agrégée (plan de correction, Phase 5) —
   * jamais un `count()` par promo dans une boucle (règle CLAUDE.md #14).
   * Même logique de fenêtre d'ignore que `pendingModerationQueryBuilder`.
   */
  async getReasonBreakdown(promoIds: string[]): Promise<Record<string, Record<string, number>>> {
    if (promoIds.length === 0) return {};

    const rows = await this.reports
      .createQueryBuilder('report')
      .innerJoin(Promo, 'promo', 'promo.id = report.promoId')
      .select('report.promoId', 'promoId')
      .addSelect('report.reason', 'reason')
      .addSelect('COUNT(DISTINCT report.deviceId)', 'count')
      .where('report.promoId IN (:...promoIds)', { promoIds })
      .andWhere(
        `("promo"."verifiedOkAt" IS NULL
          OR "report"."createdAt" > "promo"."verifiedOkAt"
          OR NOW() > "promo"."verifiedOkAt" + make_interval(days => :ignoreWindowDays))`,
        { ignoreWindowDays: IGNORE_WINDOW_DAYS },
      )
      .groupBy('report.promoId')
      .addGroupBy('report.reason')
      .getRawMany<{ promoId: string; reason: ReportReason | null; count: string }>();

    const breakdown: Record<string, Record<string, number>> = {};
    for (const row of rows) {
      breakdown[row.promoId] ??= {};
      breakdown[row.promoId][row.reason ?? 'autre'] = Number(row.count);
    }
    return breakdown;
  }
}

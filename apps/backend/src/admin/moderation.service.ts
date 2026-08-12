import { Injectable } from '@nestjs/common';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { PaginatedResult } from '../common/pagination/paginated-result';
import { Promo } from '../promo/entities/promo.entity';
import { PromoService } from '../promo/promo.service';
import { ReportService } from '../report/report.service';
import { NotificationService } from '../notification/notification.service';
import {
  NotificationRecipientType,
  NotificationType,
} from '../notification/entities/notification.entity';

/** Orchestration modération (file d'attente + résolutions) — extrait d'AdminController (audit). */
@Injectable()
export class ModerationService {
  constructor(
    private readonly promoService: PromoService,
    private readonly reportService: ReportService,
    private readonly auditLogService: AuditLogService,
    private readonly notificationService: NotificationService,
  ) {}

  /**
   * ⚠️ **File nationale depuis le 2026-08-13** : ni portée d'agent, ni filtre
   * géographique. Elle n'a plus aucun paramètre de cadrage — c'est un point
   * ouvert, pas un aboutissement (voir `pendingModerationQueryBuilder`).
   */
  async queue(
    page: number,
    limit: number,
  ): Promise<
    PaginatedResult<{
      promo: Promo;
      activeReportCount: number;
      reasonBreakdown: Record<string, number>;
    }>
  > {
    const pending = await this.reportService.listPendingModeration(page, limit);
    const promoIds = pending.items.map(({ promoId }) => promoId);
    const promos = await this.promoService.findByIds(promoIds);
    const promoById = new Map(promos.map((promo) => [promo.id, promo]));
    const reasonBreakdownByPromoId =
      await this.reportService.getReasonBreakdown(promoIds);
    const items = pending.items
      .filter(({ promoId }) => promoById.has(promoId))
      .map(({ promoId, activeReportCount }) => ({
        promo: promoById.get(promoId)!,
        activeReportCount,
        reasonBreakdown: reasonBreakdownByPromoId[promoId] ?? {},
      }));
    return { ...pending, items };
  }

  /** Le rôle agent modère aussi désormais (scopé communes, vérifié en amont dans AdminController). */
  async masquer(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    await this.promoService.resolveMasquer(promoId);
    await this.notificationService.create(
      NotificationType.PROMO_HIDDEN,
      NotificationRecipientType.COMMERCANT,
      promo.commercantId,
      `Votre promo « ${promo.description} » a été masquée suite à des signalements.`,
      promoId,
      {
        promoDescription: promo.description,
      },
    );
    await this.record(actorType, actorId, 'moderation_masquer', promoId);
  }

  async verifierOk(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    await this.promoService.resolveVerifieOk(promoId);
    await this.notificationService.create(
      NotificationType.PROMO_VERIFIED,
      NotificationRecipientType.COMMERCANT,
      promo.commercantId,
      `Votre promo « ${promo.description} » a été vérifiée et validée.`,
      promoId,
      {
        promoDescription: promo.description,
      },
    );
    await this.record(actorType, actorId, 'moderation_verifier_ok', promoId);
  }

  async avertir(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    await this.promoService.resolveAvertir(promoId);
    await this.notificationService.create(
      NotificationType.PROMO_WARNED,
      NotificationRecipientType.COMMERCANT,
      promo.commercantId,
      `Votre promo « ${promo.description} » a reçu plusieurs signalements et a été repassée en brouillon. Vérifiez-la puis republiez-la.`,
      promoId,
      {
        promoDescription: promo.description,
      },
    );
    await this.record(actorType, actorId, 'moderation_avertir', promoId);
  }

  private async record(
    actorType: AuditActorType,
    actorId: string,
    action: string,
    promoId: string,
  ): Promise<void> {
    await this.auditLogService.record({
      actorType,
      actorId,
      action,
      targetType: 'promo',
      targetId: promoId,
    });
  }
}

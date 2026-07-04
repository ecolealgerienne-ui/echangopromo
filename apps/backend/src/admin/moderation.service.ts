import { Injectable } from '@nestjs/common';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { PromoService } from '../promo/promo.service';
import { ReportService } from '../report/report.service';

/** Orchestration modération (file d'attente + résolutions) — extrait d'AdminController (audit). */
@Injectable()
export class ModerationService {
  constructor(
    private readonly promoService: PromoService,
    private readonly reportService: ReportService,
    private readonly auditLogService: AuditLogService,
  ) {}

  async queue() {
    const pending = await this.reportService.listPendingModeration();
    return Promise.all(
      pending.map(async ({ promoId, activeReportCount }) => ({
        promo: await this.promoService.findByIdOrFail(promoId),
        activeReportCount,
      })),
    );
  }

  async masquer(adminId: string, promoId: string): Promise<void> {
    await this.promoService.resolveMasquer(promoId);
    await this.record(adminId, 'moderation_masquer', promoId);
  }

  async verifierOk(adminId: string, promoId: string): Promise<void> {
    await this.promoService.resolveVerifieOk(promoId);
    await this.record(adminId, 'moderation_verifier_ok', promoId);
  }

  async avertir(adminId: string, promoId: string): Promise<void> {
    await this.promoService.resolveAvertir(promoId);
    await this.record(adminId, 'moderation_avertir', promoId);
  }

  private async record(
    adminId: string,
    action: string,
    promoId: string,
  ): Promise<void> {
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: adminId,
      action,
      targetType: 'promo',
      targetId: promoId,
    });
  }
}

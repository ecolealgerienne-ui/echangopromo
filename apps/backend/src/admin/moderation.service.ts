import { Injectable } from '@nestjs/common';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { PaginatedResult } from '../common/pagination/paginated-result';
import { Promo, PromoModerationStatus } from '../promo/entities/promo.entity';
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

  /**
   * ⚠️ **Le commentaire d'origine disait « scopé communes, vérifié en amont
   * dans AdminController » — c'est faux depuis le 2026-08-13.** Rien n'est
   * scopé, rien n'est vérifié en amont : tout agent modère tout le parc.
   *
   * `expected` est l'état que le modérateur avait à l'écran. Il n'est comparé
   * à rien **ici** : c'est l'`UPDATE` conditionnel de `PromoService` qui
   * arbitre. Comparer d'abord puis écrire rouvrirait très exactement la course
   * qu'on ferme (règle 13). Il ne fait que traverser.
   */
  async masquer(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
    expected: PromoModerationStatus,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    // ⚠️ AVANT de résoudre — voir `contexteDeDecision`.
    const contexte = await this.contexteDeDecision(promoId);
    await this.promoService.resolveMasquer(promoId, expected);
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
    await this.record(
      actorType,
      actorId,
      'moderation_masquer',
      promoId,
      contexte,
    );
  }

  async verifierOk(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
    expected: PromoModerationStatus,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    // ⚠️ AVANT de résoudre — voir `contexteDeDecision`.
    const contexte = await this.contexteDeDecision(promoId);
    await this.promoService.resolveVerifieOk(promoId, expected);
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
    await this.record(
      actorType,
      actorId,
      'moderation_verifier_ok',
      promoId,
      contexte,
    );
  }

  async avertir(
    actorType: AuditActorType,
    actorId: string,
    promoId: string,
    expected: PromoModerationStatus,
  ): Promise<void> {
    const promo = await this.promoService.findByIdOrFail(promoId);
    // ⚠️ AVANT de résoudre — voir `contexteDeDecision`.
    const contexte = await this.contexteDeDecision(promoId);
    await this.promoService.resolveAvertir(promoId, expected);
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
    await this.record(
      actorType,
      actorId,
      'moderation_avertir',
      promoId,
      contexte,
    );
  }

  /**
   * ⚠️ **Le contexte de la décision est enregistré avec elle** (2026-08-13).
   *
   * Les trois routes ne prenaient **aucun corps** : le `{"reason": …}` que trois
   * bancs leur envoyaient depuis des semaines était jeté en silence par
   * `whitelist: true`. Une décision de modération n'avait donc **aucun motif
   * enregistré** — le journal disait « untel a masqué la promo X », sans dire
   * pourquoi elle était en file.
   *
   * ⚠️ **Le motif enregistré est celui des SIGNALEURS, pas du modérateur**, et
   * c'est un choix. Demander sa motivation au modérateur exigerait un champ de
   * saisie sur trois écrans, et une boîte de dialogue par geste ralentirait
   * une file qu'on traite au rythme d'un tap. Le décompte par motif, lui, est
   * déjà calculé par le produit — c'est ce que la file affiche à côté de chaque
   * promo — et il répond à la question qui compte pour un audit : **sur quoi
   * cette personne a-t-elle décidé ?**
   *
   * ⚠️ `activeReportCount` est **compté ici et non déduit** de la longueur du
   * décompte : les deux mesurent des choses différentes (appareils distincts
   * vs signalements par motif) et les confondre donnerait un chiffre faux dès
   * qu'un appareil signale deux fois.
   *
   * Une décision prise hors file (depuis la liste de toutes les promos) porte
   * un décompte vide — c'est l'information juste : personne ne l'avait
   * signalée.
   *
   * ── ⚠️ À appeler AVANT la résolution, et ce n'est pas une préférence ───────
   *
   * `resolveVerifieOk` pose `verifiedOkAt = now`, et **les deux requêtes
   * ci-dessous filtrent sur ce champ** (fenêtre d'ignore de 30 jours). Mesuré
   * après la résolution, le contexte d'un « vérifier OK » serait donc
   * systématiquement **zéro signalement, aucun motif** — le journal dirait que
   * le modérateur a tranché sur rien, au moment précis où il vient de trancher
   * sur trois signalements.
   *
   * C'est le miroir du piège déjà payé le 2026-08-05, où des valeurs de
   * référence lues trop TÔT décrivaient un état disparu. Ici c'est trop TARD,
   * et le remède est le même : **mesurer au plus près du geste**, du bon côté.
   */
  private async contexteDeDecision(
    promoId: string,
  ): Promise<Record<string, unknown>> {
    const parMotif = await this.reportService.getReasonBreakdown([promoId]);
    const signalements = await this.reportService.countActiveReports(promoId);
    return {
      signalementsActifs: signalements,
      motifs: parMotif[promoId] ?? {},
    };
  }

  private async record(
    actorType: AuditActorType,
    actorId: string,
    action: string,
    promoId: string,
    contexte: Record<string, unknown>,
  ): Promise<void> {
    await this.auditLogService.record({
      actorType,
      actorId,
      action,
      targetType: 'promo',
      targetId: promoId,
      metadata: contexte,
    });
  }
}

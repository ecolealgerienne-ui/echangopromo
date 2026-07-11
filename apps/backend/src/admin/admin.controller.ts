import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AgentService } from '../agent/agent.service';
import { AssignCommunesDto } from '../agent/dto/assign-communes.dto';
import { CreateAgentDto } from '../agent/dto/create-agent.dto';
import { TransferCommunesDto } from '../agent/dto/transfer-communes.dto';
import { AuditLogService } from '../audit-log/audit-log.service';
import { ListAuditLogQueryDto } from '../audit-log/dto/list-audit-log-query.dto';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { ListCommercantQueryDto } from '../commercant/dto/list-commercant-query.dto';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { SENSITIVE_ACTION_THROTTLE, STRICT_THROTTLE } from '../common/throttle';
import { ListPromoAdminQueryDto } from '../promo/dto/list-promo-admin-query.dto';
import { Promo } from '../promo/entities/promo.entity';
import { PromoService } from '../promo/promo.service';
import { ReportService } from '../report/report.service';
import { StorageService } from '../storage/storage.service';
import { AdminService } from './admin.service';
import { LoginAdminDto } from './dto/login-admin.dto';
import { ModerationService } from './moderation.service';

@Controller('admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly agentService: AgentService,
    private readonly commercantService: CommercantService,
    private readonly promoService: PromoService,
    private readonly reportService: ReportService,
    private readonly authService: AuthService,
    private readonly auditLogService: AuditLogService,
    private readonly moderationService: ModerationService,
    private readonly storageService: StorageService,
  ) {}

  @Throttle(STRICT_THROTTLE)
  @Post('login')
  async login(@Body() dto: LoginAdminDto) {
    const admin = await this.adminService.login(dto.email, dto.password);
    return {
      accessToken: this.authService.issueToken(
        admin.id,
        'admin',
        admin.tokenVersion,
      ),
    };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.adminService.findByIdOrFail(user.sub);
  }

  /** Révoque tous les JWT déjà émis pour ce compte (device perdu/volé) — audit V1 §1. */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('me/revoke-token')
  async revokeOwnToken(@CurrentUser() user: AuthTokenPayload) {
    await this.adminService.revokeOwnTokens(user.sub);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'revoke_own_token',
      targetType: 'admin',
      targetId: user.sub,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent')
  async createAgent(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreateAgentDto,
  ) {
    const agent = await this.agentService.create(dto);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'create_agent',
      targetType: 'agent',
      targetId: agent.id,
    });
    return agent;
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('agent')
  async listAgents(@Query() query: PaginationQueryDto) {
    return this.agentService.findAll(query.page, query.limit);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Patch('agent/:id/communes')
  async assignCommunes(
    @Param('id') agentId: string,
    @Body() dto: AssignCommunesDto,
  ) {
    return this.agentService.assignCommunes(agentId, dto.communeIds);
  }

  /** Révoque les JWT déjà émis pour cet agent (device perdu/volé, départ — audit règle #6). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent/:id/revoke-token')
  async revokeAgentToken(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') agentId: string,
  ) {
    await this.agentService.revokeTokens(agentId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'revoke_agent_token',
      targetType: 'agent',
      targetId: agentId,
    });
    return { ok: true };
  }

  /** Transfère un lot de communes d'un agent à un autre (specs §3.4). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent/transfer-communes')
  async transferCommunes(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: TransferCommunesDto,
  ) {
    await this.agentService.transferCommunes(
      dto.communeIds,
      dto.fromAgentId,
      dto.toAgentId,
    );
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'transfer_communes',
      targetType: 'agent',
      targetId: dto.toAgentId,
      metadata: { communeIds: dto.communeIds, fromAgentId: dto.fromAgentId },
    });
    return { ok: true };
  }

  /**
   * DTO explicite plutôt qu'un spread d'entité (règle #4) — la file de
   * modération n'exposait ni photoUrl (jamais calculé, `photoKey` est
   * @Exclude()) ni le contact du commerçant, rendant la décision de
   * modération difficile sans ces informations. Partagé entre la file
   * automatique et la liste globale (`/admin/promo`, Phase 2).
   */
  private toAdminPromoJson(promo: Promo) {
    return {
      id: promo.id,
      description: promo.description,
      prixAvant: promo.prixAvant,
      prixApres: promo.prixApres,
      categorie: promo.categorie,
      photoUrl: promo.photoKey ? this.storageService.buildPublicUrl(promo.photoKey) : null,
      lifecycleStatus: promo.lifecycleStatus,
      moderationStatus: promo.moderationStatus,
      dateFin: promo.dateFin,
      commercantId: promo.commercant.id,
      commercantNom: promo.commercant.nom,
      commercantTelephone: promo.commercant.telephone,
    };
  }

  /**
   * Agent = modérateur (plan de correction, Phase 2) : `undefined` pour un
   * admin (vue globale), la liste des communes de l'agent sinon — jamais
   * `[]` silencieux qui laisserait passer une requête non filtrée par erreur
   * ailleurs (chaque appelant traite explicitement le cas `undefined`).
   */
  private async scopedCommuneIds(user: AuthTokenPayload): Promise<string[] | undefined> {
    if (user.role !== 'agent') return undefined;
    const agent = await this.agentService.findByIdOrFail(user.sub);
    return agent.communes.map((commune) => commune.id);
  }

  /** Garde IDOR (règle #1) : un agent ne peut modérer que les promos de ses propres communes. */
  private async assertCanModerate(user: AuthTokenPayload, promoId: string): Promise<void> {
    if (user.role !== 'agent') return;
    const promo = await this.promoService.findByIdOrFail(promoId);
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertCommuneMatches(
      promo.commercantId,
      agent.communes.map((commune) => commune.id),
    );
  }

  private actorType(role: string): AuditActorType {
    return role === 'agent' ? AuditActorType.AGENT : AuditActorType.ADMIN;
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('moderation/queue')
  async moderationQueue(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: PaginationQueryDto,
  ) {
    const communeIds = await this.scopedCommuneIds(user);
    const result = await this.moderationService.queue(query.page, query.limit, communeIds);
    return {
      ...result,
      items: result.items.map(({ promo, activeReportCount }) => ({
        ...this.toAdminPromoJson(promo),
        activeReportCount,
      })),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/masquer')
  async masquer(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.assertCanModerate(user, promoId);
    await this.moderationService.masquer(this.actorType(user.role), user.sub, promoId);
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/verifier-ok')
  async verifierOk(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.assertCanModerate(user, promoId);
    await this.moderationService.verifierOk(this.actorType(user.role), user.sub, promoId);
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/avertir')
  async avertir(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.assertCanModerate(user, promoId);
    await this.moderationService.avertir(this.actorType(user.role), user.sub, promoId);
    return { ok: true };
  }

  /**
   * Vue globale de toutes les promos (plan de correction, Phase 2) — la
   * file de modération n'expose que celles ayant atteint le seuil de
   * signalements ; ceci permet de repérer et masquer un contenu
   * problématique directement, sans attendre 3 signalements clients.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('promo')
  async listPromos(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: ListPromoAdminQueryDto,
  ) {
    const communeIds = await this.scopedCommuneIds(user);
    const result = await this.promoService.findAllForAdmin(query, communeIds);
    return {
      ...result,
      items: result.items.map((promo) => this.toAdminPromoJson(promo)),
    };
  }

  /**
   * Liste + recherche sur l'ensemble des commerçants (plan de correction,
   * Phase 2) — jusqu'ici seule la file registre (en attente) était
   * consultable, impossible de retrouver un compte précis autrement qu'en
   * requêtant la base directement.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('commercant')
  async listCommercants(@Query() query: ListCommercantQueryDto) {
    const result = await this.commercantService.findAllForAdmin(query);
    return {
      ...result,
      items: result.items.map((commercant) => ({
        id: commercant.id,
        nom: commercant.nom,
        telephone: commercant.telephone,
        communeId: commercant.communeId,
        accountState: commercant.accountState,
        originVerification: commercant.originVerification,
        registreStatus: commercant.registreStatus,
        suspended: commercant.deletedAt !== null,
        createdAt: commercant.createdAt,
      })),
    };
  }

  /** Suspend un compte (soft delete réutilisé — même effet que l'auto-suppression). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/suspend')
  async suspendCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') commercantId: string,
  ) {
    await this.commercantService.deleteAccount(commercantId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'commercant_suspend',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/reactivate')
  async reactivateCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') commercantId: string,
  ) {
    await this.commercantService.reactivateAccount(commercantId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'commercant_reactivate',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /** File d'attente des vérifications registre en attente (specs §3.4). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('commercant/registre/queue')
  async registreQueue(@Query() query: PaginationQueryDto) {
    const result = await this.commercantService.findPendingRegistreVerification(
      query.page,
      query.limit,
    );
    return {
      ...result,
      items: result.items.map((commercant) => ({
        id: commercant.id,
        nom: commercant.nom,
        telephone: commercant.telephone,
        registreUrl: commercant.registreKey
          ? this.storageService.buildPublicUrl(commercant.registreKey)
          : null,
        createdAt: commercant.createdAt,
      })),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/registre/valider')
  async validerRegistre(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') commercantId: string,
  ) {
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      true,
    );
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'registre_valider',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /** PIN oublié : pas d'OTP, seul l'admin peut effacer le PIN (§3.2). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/reset-pin')
  async resetPin(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') commercantId: string,
  ) {
    await this.commercantService.adminResetPin(commercantId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'commercant_reset_pin',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/registre/rejeter')
  async rejeterRegistre(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') commercantId: string,
  ) {
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      false,
    );
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'registre_rejeter',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * Journal d'audit consultable (plan de correction, Phase 3) — admin only,
   * y compris les actions enregistrées par un agent (transfert de communes,
   * modération...) : un agent ne voit pas ce journal, seul l'admin doit
   * pouvoir retracer "qui a fait quoi".
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('audit-log')
  async auditLog(@Query() query: ListAuditLogQueryDto) {
    return this.auditLogService.findAll(query.page, query.limit, query.actorType);
  }

  /** Dashboard global admin (specs §3.4). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('dashboard')
  async dashboard() {
    const [commercesActifs, promosPubliees, signalementsEnAttente] =
      await Promise.all([
        this.commercantService.countActive(),
        this.promoService.countVisible(),
        this.reportService.countPendingModeration(),
      ]);

    return {
      commercesActifs,
      promosPubliees,
      signalementsEnAttente,
    };
  }
}

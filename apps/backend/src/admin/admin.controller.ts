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
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { SENSITIVE_ACTION_THROTTLE, STRICT_THROTTLE } from '../common/throttle';
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

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('moderation/queue')
  async moderationQueue(@Query() query: PaginationQueryDto) {
    const result = await this.moderationService.queue(query.page, query.limit);
    return {
      ...result,
      // DTO explicite plutôt qu'un spread d'entité (règle #4) — la file de
      // modération n'exposait ni photoUrl (jamais calculé, `photoKey` est
      // @Exclude()) ni le contact du commerçant, rendant la décision de
      // modération difficile sans ces informations.
      items: result.items.map(({ promo, activeReportCount }) => ({
        id: promo.id,
        description: promo.description,
        prixAvant: promo.prixAvant,
        prixApres: promo.prixApres,
        categorie: promo.categorie,
        photoUrl: promo.photoKey ? this.storageService.buildPublicUrl(promo.photoKey) : null,
        lifecycleStatus: promo.lifecycleStatus,
        moderationStatus: promo.moderationStatus,
        activeReportCount,
        commercantId: promo.commercant.id,
        commercantNom: promo.commercant.nom,
        commercantTelephone: promo.commercant.telephone,
      })),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/masquer')
  async masquer(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.moderationService.masquer(user.sub, promoId);
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/verifier-ok')
  async verifierOk(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.moderationService.verifierOk(user.sub, promoId);
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/avertir')
  async avertir(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.moderationService.avertir(user.sub, promoId);
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

import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AgentService } from '../agent/agent.service';
import { AssignZoneDto } from '../agent/dto/assign-zone.dto';
import { CreateAgentDto } from '../agent/dto/create-agent.dto';
import { TransferZoneDto } from '../agent/dto/transfer-zone.dto';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { STRICT_THROTTLE } from '../common/throttle';
import { PromoService } from '../promo/promo.service';
import { ReportService } from '../report/report.service';
import { AdminService } from './admin.service';
import { LoginAdminDto } from './dto/login-admin.dto';

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
  ) {}

  @Throttle(STRICT_THROTTLE)
  @Post('login')
  async login(@Body() dto: LoginAdminDto) {
    const admin = await this.adminService.login(dto.email, dto.password);
    return { accessToken: this.authService.issueToken(admin.id, 'admin') };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.adminService.findByIdOrFail(user.sub);
  }

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
  async listAgents() {
    return this.agentService.findAll();
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Patch('agent/:id/zone')
  async assignZone(@Param('id') agentId: string, @Body() dto: AssignZoneDto) {
    return this.agentService.assignZone(agentId, dto.zoneId ?? null);
  }

  /** Transfère une zone d'un agent à un autre (specs §3.4). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent/transfer-zone')
  async transferZone(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: TransferZoneDto,
  ) {
    await this.agentService.transferZone(
      dto.zoneId,
      dto.fromAgentId,
      dto.toAgentId,
    );
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'transfer_zone',
      targetType: 'zone',
      targetId: dto.zoneId,
      metadata: { fromAgentId: dto.fromAgentId, toAgentId: dto.toAgentId },
    });
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('moderation/queue')
  async moderationQueue() {
    const pending = await this.reportService.listPendingModeration();
    return Promise.all(
      pending.map(async ({ promoId, activeReportCount }) => ({
        promo: await this.promoService.findByIdOrFail(promoId),
        activeReportCount,
      })),
    );
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/masquer')
  async masquer(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.promoService.resolveMasquer(promoId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'moderation_masquer',
      targetType: 'promo',
      targetId: promoId,
    });
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/verifier-ok')
  async verifierOk(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.promoService.resolveVerifieOk(promoId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'moderation_verifier_ok',
      targetType: 'promo',
      targetId: promoId,
    });
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/avertir')
  async avertir(
    @CurrentUser() user: AuthTokenPayload,
    @Param('promoId') promoId: string,
  ) {
    await this.promoService.resolveAvertir(promoId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'moderation_avertir',
      targetType: 'promo',
      targetId: promoId,
    });
    return { ok: true };
  }

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
    const [commercesActifs, promosPubliees, moderationQueue] =
      await Promise.all([
        this.commercantService.countActive(),
        this.promoService.countVisible(),
        this.reportService.listPendingModeration(),
      ]);

    return {
      commercesActifs,
      promosPubliees,
      signalementsEnAttente: moderationQueue.length,
    };
  }
}

import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AgentService } from '../agent/agent.service';
import { AssignZoneDto } from '../agent/dto/assign-zone.dto';
import { CreateAgentDto } from '../agent/dto/create-agent.dto';
import { TransferZoneDto } from '../agent/dto/transfer-zone.dto';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
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
  ) {}

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
  async createAgent(@Body() dto: CreateAgentDto) {
    return this.agentService.create(dto);
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
  async transferZone(@Body() dto: TransferZoneDto) {
    await this.agentService.transferZone(
      dto.zoneId,
      dto.fromAgentId,
      dto.toAgentId,
    );
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
  async masquer(@Param('promoId') promoId: string) {
    await this.promoService.resolveMasquer(promoId);
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/verifier-ok')
  async verifierOk(@Param('promoId') promoId: string) {
    await this.promoService.resolveVerifieOk(promoId);
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('moderation/:promoId/avertir')
  async avertir(@Param('promoId') promoId: string) {
    await this.promoService.resolveAvertir(promoId);
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/registre/valider')
  async validerRegistre(@Param('id') commercantId: string) {
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      true,
    );
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('commercant/:id/registre/rejeter')
  async rejeterRegistre(@Param('id') commercantId: string) {
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      false,
    );
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

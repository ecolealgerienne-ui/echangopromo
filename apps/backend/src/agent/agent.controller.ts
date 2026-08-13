import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { CreateCommercantByAgentDto } from '../commercant/dto/create-commercant-by-agent.dto';
import { AUTH_THROTTLE, SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { AgentService } from './agent.service';
import { LoginAgentDto } from './dto/login-agent.dto';

@Controller('agent')
export class AgentController {
  constructor(
    private readonly agentService: AgentService,
    private readonly commercantService: CommercantService,
    private readonly authService: AuthService,
    private readonly auditLogService: AuditLogService,
  ) {}

  @Throttle(AUTH_THROTTLE)
  @Post('login')
  async login(@Body() dto: LoginAgentDto) {
    const agent = await this.agentService.login(dto.email, dto.password);
    return {
      accessToken: this.authService.issueToken(
        agent.id,
        'agent',
        agent.tokenVersion,
      ),
    };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.agentService.findByIdOrFail(user.sub);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('commercant')
  async createCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreateCommercantByAgentDto,
  ) {
    // ⚠️ Le refus `COMMERCANT_NOT_IN_AGENT_COMMUNES` était ici jusqu'au
    // 2026-08-13. La sémantique de cette route change : « je crée un commerce
    // dans MES communes » devient « je crée un commerce n'importe où ».
    // `findByIdOrFail` reste nécessaire — `agent.id` alimente
    // `createdByAgentId` et le journal d'audit ci-dessous.
    const agent = await this.agentService.findByIdOrFail(user.sub);
    const commercant = await this.commercantService.createByAgent(
      dto,
      agent.id,
    );
    await this.auditLogService.record({
      actorType: AuditActorType.AGENT,
      actorId: agent.id,
      action: 'create_commercant',
      targetType: 'commercant',
      targetId: commercant.id,
    });
    return commercant;
  }
}

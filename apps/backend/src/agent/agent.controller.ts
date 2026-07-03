import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { CreateCommercantByAgentDto } from '../commercant/dto/create-commercant-by-agent.dto';
import { AgentService } from './agent.service';
import { LoginAgentDto } from './dto/login-agent.dto';

@Controller('agent')
export class AgentController {
  constructor(
    private readonly agentService: AgentService,
    private readonly commercantService: CommercantService,
    private readonly authService: AuthService,
  ) {}

  @Post('login')
  async login(@Body() dto: LoginAgentDto) {
    const agent = await this.agentService.login(dto.email, dto.password);
    return { accessToken: this.authService.issueToken(agent.id, 'agent') };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.agentService.findByIdOrFail(user.sub);
  }

  /** Liste des commerces de la zone de l'agent connecté, avec statut de tournée (specs §3.3). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Get('zone/commerces')
  async zoneCommerces(@CurrentUser() user: AuthTokenPayload) {
    const agent = await this.agentService.findByIdOrFail(user.sub);
    if (!agent.zoneId) {
      throw new BadRequestException("Cet agent n'est rattaché à aucune zone");
    }
    return this.commercantService.listByZoneWithVisitStatus(agent.zoneId);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('commercant')
  async createCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreateCommercantByAgentDto,
  ) {
    const agent = await this.agentService.findByIdOrFail(user.sub);
    return this.commercantService.createByAgent(dto, agent.id, agent.zoneId);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('commercant/:id/initiate-claim')
  async initiateClaim(@Param('id') commercantId: string) {
    await this.commercantService.initiateClaim(commercantId);
    return { ok: true };
  }
}

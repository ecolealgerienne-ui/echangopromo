import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AgentService } from '../agent/agent.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { Promo } from './entities/promo.entity';
import { PromoService } from './promo.service';

@Controller('promo')
export class PromoController {
  constructor(
    private readonly promoService: PromoService,
    private readonly storageService: StorageService,
    private readonly agentService: AgentService,
    private readonly commercantService: CommercantService,
  ) {}

  /**
   * DTO de sortie explicite plutôt qu'un spread de l'entité (`{...promo}`) :
   * un spread transforme l'instance en objet plain et désactiverait
   * silencieusement les `@Exclude()` si l'entité en gagnait un jour ;
   * ça exclut aussi `photoKey`, qui pour les promos créées par un agent
   * contient l'UUID de l'**agent** (pas du commerçant) — un identifiant
   * interne qui n'a rien à faire dans une réponse publique.
   */
  private toClientJson(promo: Promo) {
    return {
      id: promo.id,
      commercantId: promo.commercantId,
      commercantNom: promo.commercant?.nom ?? null,
      description: promo.description,
      prixAvant: promo.prixAvant,
      prixApres: promo.prixApres,
      categorie: promo.categorie,
      dateFin: promo.dateFin,
      lifecycleStatus: promo.lifecycleStatus,
      moderationStatus: promo.moderationStatus,
      photoUrl: this.storageService.buildPublicUrl(promo.photoKey),
      createdAt: promo.createdAt,
    };
  }

  /**
   * Un commerçant ne peut agir que sur ses propres promos ; un agent, que
   * sur celles des commerçants de sa zone (même pattern IDOR que le reste
   * du module commerçant).
   */
  private async assertCanManage(
    user: AuthTokenPayload,
    promo: Promo,
  ): Promise<void> {
    if (user.role === 'commercant') {
      if (promo.commercantId !== user.sub) {
        throw new ForbiddenException("Cette promo n'appartient pas à ce commerçant");
      }
      return;
    }
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertZoneMatches(
      promo.commercantId,
      agent.zoneId,
    );
  }

  @Get()
  async list(@Query() query: ListPromoQueryDto) {
    const promos = await this.promoService.findActiveForClient(query);
    return promos.map((promo) => this.toClientJson(promo));
  }

  @Get(':id')
  async detail(@Param('id') id: string, @DeviceId() deviceId: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.promoService.recordView(id, deviceId);
    return this.toClientJson(promo);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Post()
  async create(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreatePromoDto,
  ) {
    return this.promoService.create(user.sub, dto);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/all')
  async mine(@CurrentUser() user: AuthTokenPayload) {
    const promos = await this.promoService.listByCommercant(user.sub);
    const viewCounts = await this.promoService.getViewCounts(
      promos.map((p) => p.id),
    );
    return promos.map((promo) => ({
      ...this.toClientJson(promo),
      viewCount: viewCounts[promo.id] ?? 0,
    }));
  }

  /** IDOR corrigé : un agent ne peut publier que pour un commerçant de sa propre zone. */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('agent/:commercantId')
  async createByAgent(
    @CurrentUser() user: AuthTokenPayload,
    @Param('commercantId') commercantId: string,
    @Body() dto: CreatePromoDto,
  ) {
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertZoneMatches(commercantId, agent.zoneId);
    return this.promoService.create(commercantId, dto);
  }

  /** Édition ouverte au commerçant propriétaire, en plus de l'agent (auparavant agent uniquement). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Patch(':id')
  async update(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') id: string,
    @Body() dto: UpdatePromoDto,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.assertCanManage(user, promo);
    return this.promoService.update(id, dto);
  }

  /** Publie un brouillon, ou republie une promo arrêtée/expirée (specs §3.2). */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Post(':id/publish')
  async publish(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') id: string,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.assertCanManage(user, promo);
    return this.promoService.publish(id);
  }

  /** Arrêt volontaire (ex. rupture de stock) — libère un slot sur le plafond de 5. */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Post(':id/stop')
  async stop(@CurrentUser() user: AuthTokenPayload, @Param('id') id: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.assertCanManage(user, promo);
    return this.promoService.stop(id);
  }
}

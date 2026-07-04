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
      produit: promo.produit,
      prixAvant: promo.prixAvant,
      prixApres: promo.prixApres,
      categorie: promo.categorie,
      dateFin: promo.dateFin,
      status: promo.status,
      photoUrl: this.storageService.buildPublicUrl(promo.photoKey),
      createdAt: promo.createdAt,
    };
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

  /** IDOR corrigé : un agent ne peut modifier que les promos de commerçants de sa zone. */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Patch(':id')
  async update(
    @CurrentUser() user: AuthTokenPayload,
    @Param('id') id: string,
    @Body() dto: UpdatePromoDto,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertZoneMatches(
      promo.commercantId,
      agent.zoneId,
    );
    return this.promoService.update(id, dto);
  }
}

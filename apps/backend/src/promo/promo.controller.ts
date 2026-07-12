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
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { ForbiddenAppException, NotFoundAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { Promo, VISIBLE_MODERATION_STATUSES } from './entities/promo.entity';
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
   * ça exclut aussi `photoKeys`, qui pour les promos créées par un agent
   * contient l'UUID de l'**agent** (pas du commerçant) — un identifiant
   * interne qui n'a rien à faire dans une réponse publique.
   *
   * `includeKeys` réexpose les clés S3 brutes (pas seulement les URLs) —
   * réservé à `GET /promo/me/all` (propriétaire authentifié uniquement) :
   * l'écran d'édition en a besoin pour renvoyer les photos inchangées sans
   * les réuploader, sans jamais les exposer publiquement.
   */
  private toClientJson(promo: Promo, options?: { includeKeys?: boolean }) {
    const photoUrls = promo.photoKeys.map((key) => this.storageService.buildPublicUrl(key));
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
      photoUrls,
      // Miniature de la 1ère photo (listes, audit performance 2026-07-12) —
      // retombe sur la photo complète si la génération a échoué (best-effort,
      // voir `PromoService.tryGenerateThumbnail`), jamais `null` tant qu'il y
      // a au moins une photo.
      thumbnailUrl: promo.thumbnailKey
        ? this.storageService.buildPublicUrl(promo.thumbnailKey)
        : (photoUrls[0] ?? null),
      ...(options?.includeKeys ? { photoKeys: promo.photoKeys } : {}),
      createdAt: promo.createdAt,
    };
  }

  /**
   * Un commerçant ne peut agir que sur ses propres promos ; un agent, que
   * sur celles des commerçants de ses communes (même pattern IDOR que le
   * reste du module commerçant).
   */
  private async assertCanManage(
    user: AuthTokenPayload,
    promo: Promo,
  ): Promise<void> {
    if (user.role === 'commercant') {
      if (promo.commercantId !== user.sub) {
        throw new ForbiddenAppException(
          ErrorCode.PROMO_NOT_OWNED_BY_COMMERCANT,
          "Cette promo n'appartient pas à ce commerçant",
        );
      }
      return;
    }
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertCommuneMatches(
      promo.commercantId,
      agent.communes.map((commune) => commune.id),
    );
  }

  @Get()
  async list(@Query() query: ListPromoQueryDto) {
    const result = await this.promoService.findActiveForClient(query);
    return { ...result, items: result.items.map((promo) => this.toClientJson(promo)) };
  }

  /**
   * Route publique, non authentifiée (accessible via lien partagé/App
   * Links `/p/:id`) — `findByIdOrFail` ne filtre par construction aucun
   * statut (utilisé aussi par les flux commerçant/agent qui doivent
   * pouvoir accéder à leurs propres promos quel que soit leur statut). Sans
   * ce filtre ici, une promo masquée par un modérateur restait pourtant
   * intégralement consultable par quiconque connaissait son id, simplement
   * absente du fil — `VISIBLE_MODERATION_STATUSES` est la même règle que
   * `findActiveForClient`, appliquée ici au lieu de diverger.
   */
  @Get(':id')
  async detail(@Param('id') id: string, @DeviceId() deviceId: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    if (!VISIBLE_MODERATION_STATUSES.includes(promo.moderationStatus)) {
      throw new NotFoundAppException(ErrorCode.PROMO_NOT_FOUND, 'Promo introuvable');
    }
    await this.promoService.recordView(id, deviceId);
    return this.toClientJson(promo);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
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
  async mine(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: PaginationQueryDto,
  ) {
    const result = await this.promoService.listByCommercant(
      user.sub,
      query.page,
      query.limit,
    );
    const viewCounts = await this.promoService.getViewCounts(
      result.items.map((p) => p.id),
    );
    return {
      ...result,
      items: result.items.map((promo) => ({
        ...this.toClientJson(promo, { includeKeys: true }),
        viewCount: viewCounts[promo.id] ?? 0,
      })),
    };
  }

  /** IDOR corrigé : un agent ne peut publier que pour un commerçant de ses propres communes. */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('agent/:commercantId')
  async createByAgent(
    @CurrentUser() user: AuthTokenPayload,
    @Param('commercantId') commercantId: string,
    @Body() dto: CreatePromoDto,
  ) {
    const agent = await this.agentService.findByIdOrFail(user.sub);
    await this.commercantService.assertCommuneMatches(
      commercantId,
      agent.communes.map((commune) => commune.id),
    );
    return this.promoService.create(commercantId, dto);
  }

  /** Édition ouverte au commerçant propriétaire, en plus de l'agent (auparavant agent uniquement). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
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
  @Throttle(SENSITIVE_ACTION_THROTTLE)
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
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Post(':id/stop')
  async stop(@CurrentUser() user: AuthTokenPayload, @Param('id') id: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.assertCanManage(user, promo);
    return this.promoService.stop(id);
  }
}

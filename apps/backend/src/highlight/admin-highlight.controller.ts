import {
  Body,
  Controller,
  Delete,
  Get,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { UuidParam } from '../common/decorators/uuid-param.decorator';
import { Throttle } from '@nestjs/throttler';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { StorageService } from '../storage/storage.service';
import { CreateHighlightDto } from './dto/create-highlight.dto';
import { ReorderHighlightsDto } from './dto/reorder-highlights.dto';
import { UpdateHighlightDto } from './dto/update-highlight.dto';
import { Highlight } from './entities/highlight.entity';
import { HighlightService } from './highlight.service';

/**
 * Gestion du bandeau d'accueil, réservée à l'admin — volontairement pas
 * ouverte à l'agent, contrairement à la modération : le bandeau est une
 * vitrine nationale, pas un outil de terrain scopé à quelques communes.
 *
 * Contrôleur séparé d'`AdminController` (déjà 600 lignes et dépendant de
 * sept services) plutôt qu'une neuvième dépendance injectée là-bas : les
 * routes restent sous `/admin/highlight`, le module reste autonome.
 */
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
@Controller('admin/highlight')
export class AdminHighlightController {
  constructor(
    private readonly highlightService: HighlightService,
    private readonly storageService: StorageService,
    private readonly auditLogService: AuditLogService,
  ) {}

  /**
   * Vue admin : contrairement à la vue client, elle expose aussi les
   * diapositives inactives et celles dont la cible n'est plus affichable
   * (`promoVisible: false`) — c'est précisément là qu'elles doivent être
   * visibles pour être corrigées.
   */
  private toAdminJson(highlight: Highlight, promoVisible: boolean) {
    const promo = highlight.promo;
    return {
      id: highlight.id,
      position: highlight.position,
      active: highlight.active,
      titre: highlight.titre,
      sousTitre: highlight.sousTitre,
      imageUrl: highlight.imageKey
        ? this.storageService.buildPublicUrl(highlight.imageKey)
        : null,
      // Réexposée (contrairement à la vue client) : l'écran d'édition doit
      // pouvoir renvoyer l'image inchangée sans la réuploader, même logique
      // que `photoKeys` sur `GET /promo/me/all`.
      imageKey: highlight.imageKey,
      promoId: highlight.promoId,
      promoDescription: promo?.description ?? null,
      prixAvant: promo?.prixAvant ?? null,
      prixApres: promo?.prixApres ?? null,
      promoPhotoUrl: promo?.thumbnailKey
        ? this.storageService.buildPublicUrl(promo.thumbnailKey)
        : promo?.photoKeys[0]
          ? this.storageService.buildPublicUrl(promo.photoKeys[0])
          : null,
      promoVisible,
      commercantNom: promo?.commercant?.nom ?? null,
      createdAt: highlight.createdAt,
    };
  }

  /**
   * `targetId` omis pour une action qui porte sur le bandeau entier
   * (réordonnancement) : un identifiant inventé du type `'all'` polluerait
   * le journal d'audit, qui est relu tel quel par l'écran admin.
   */
  private record(
    user: AuthTokenPayload,
    action: string,
    targetId?: string,
    metadata?: Record<string, unknown>,
  ) {
    return this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action,
      targetType: 'highlight',
      targetId,
      metadata,
    });
  }

  @Get()
  async list() {
    const items = await this.highlightService.findAllForAdmin();
    return {
      items: items.map(({ highlight, promoVisible }) =>
        this.toAdminJson(highlight, promoVisible),
      ),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Post()
  async create(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreateHighlightDto,
  ) {
    const highlight = await this.highlightService.create(dto);
    await this.record(user, 'highlight.create', highlight.id, {
      promoId: highlight.promoId,
      hasImage: highlight.imageKey !== null,
    });
    const created = await this.highlightService.findByIdForAdmin(highlight.id);
    return this.toAdminJson(created.highlight, created.promoVisible);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Post('reorder')
  async reorder(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: ReorderHighlightsDto,
  ) {
    const items = await this.highlightService.reorder(dto);
    await this.record(user, 'highlight.reorder', undefined, { ids: dto.ids });
    return {
      items: items.map(({ highlight, promoVisible }) =>
        this.toAdminJson(highlight, promoVisible),
      ),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Patch(':id')
  async update(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') id: string,
    @Body() dto: UpdateHighlightDto,
  ) {
    const highlight = await this.highlightService.update(id, dto);
    await this.record(user, 'highlight.update', id, {
      promoId: highlight.promoId,
      active: highlight.active,
    });
    const updated = await this.highlightService.findByIdForAdmin(id);
    return this.toAdminJson(updated.highlight, updated.promoVisible);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Delete(':id')
  async remove(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') id: string,
  ) {
    await this.highlightService.remove(id);
    await this.record(user, 'highlight.delete', id);
    return { deleted: true };
  }
}

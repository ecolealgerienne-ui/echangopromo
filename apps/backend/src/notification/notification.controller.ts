import { Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { UuidParam } from '../common/decorators/uuid-param.decorator';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { NotificationService } from './notification.service';
import {
  Notification,
  NotificationRecipientType,
} from './entities/notification.entity';

@Controller('notifications')
@UseGuards(JwtAuthGuard, RolesGuard)
export class NotificationController {
  constructor(private readonly notificationService: NotificationService) {}

  /**
   * **Le serveur envoie de quoi composer la phrase, pas la phrase.**
   *
   * `message` est composé côté serveur, en français, sans que rien ne connaisse
   * la langue du destinataire — dans une app qui bascule fr/en/ar depuis
   * juillet 2026. Un commerçant arabophone lisait donc du français en mise en
   * page RTL (revue 2026-08-05, règle #27).
   *
   * Le couple (`type`, `promoDescription`) suffit à reconstruire les sept
   * messages côté app (`notificationLabel`). `promoDescription` est extrait
   * **explicitement** de `metadata` plutôt que d'exposer le jsonb entier :
   * celui-ci reste `@Exclude()` et peut accueillir demain du contexte interne
   * qui n'a rien à faire chez le client.
   *
   * `message` reste servi, en **dernier recours** : une valeur ajoutée à
   * `NotificationType` avant que le miroir Dart ne la connaisse s'affichera en
   * français plutôt que pas du tout (voir `NotificationType.unknown`).
   */
  private toClientJson(notification: Notification) {
    const promoDescription = notification.metadata?.promoDescription;
    return {
      id: notification.id,
      type: notification.type,
      message: notification.message,
      promoId: notification.promoId ?? null,
      promoDescription:
        typeof promoDescription === 'string' ? promoDescription : null,
      createdAt: notification.createdAt,
      readAt: notification.readAt,
    };
  }

  /**
   * Liste les notifications non lues de l'utilisateur connecté (commercant, agent ou admin).
   * La role du JWT détermine automatiquement le type de destinataire.
   */
  @Get('unread')
  @Roles('commercant', 'agent', 'admin')
  async listUnread(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: PaginationQueryDto,
  ) {
    const recipientType = this.roleToRecipientType(user.role);
    const result = await this.notificationService.listUnread(
      recipientType,
      user.sub,
      query.page,
      query.limit,
    );
    return {
      ...result,
      items: result.items.map((n) => this.toClientJson(n)),
    };
  }

  /**
   * Historique complet (lues + non lues) de l'utilisateur connecté.
   */
  @Get()
  @Roles('commercant', 'agent', 'admin')
  async listAll(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: PaginationQueryDto,
  ) {
    const recipientType = this.roleToRecipientType(user.role);
    const result = await this.notificationService.listAll(
      recipientType,
      user.sub,
      query.page,
      query.limit,
    );
    return {
      ...result,
      items: result.items.map((n) => this.toClientJson(n)),
    };
  }

  /**
   * Compte les notifications non lues (pour un badge de compteur).
   */
  @Get('unread/count')
  @Roles('commercant', 'agent', 'admin')
  async countUnread(@CurrentUser() user: AuthTokenPayload) {
    const recipientType = this.roleToRecipientType(user.role);
    const count = await this.notificationService.countUnread(
      recipientType,
      user.sub,
    );
    return { count };
  }

  /**
   * Marque une notification spécifique comme lue.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Post(':id/read')
  @Roles('commercant', 'agent', 'admin')
  async markAsRead(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') notificationId: string,
  ) {
    const recipientType = this.roleToRecipientType(user.role);
    await this.notificationService.markAsRead(
      notificationId,
      recipientType,
      user.sub,
    );
    return { ok: true };
  }

  /**
   * Marque toutes les notifications non lues comme lues.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Post('read-all')
  @Roles('commercant', 'agent', 'admin')
  async markAllAsRead(@CurrentUser() user: AuthTokenPayload) {
    const recipientType = this.roleToRecipientType(user.role);
    await this.notificationService.markAllAsRead(recipientType, user.sub);
    return { ok: true };
  }

  private roleToRecipientType(role: string): NotificationRecipientType {
    switch (role) {
      case 'commercant':
        return NotificationRecipientType.COMMERCANT;
      case 'agent':
        return NotificationRecipientType.AGENT;
      case 'admin':
        return NotificationRecipientType.ADMIN;
      default:
        throw new Error(`Unknown role: ${role}`);
    }
  }
}

import {
  Controller,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { NotificationService } from './notification.service';
import { NotificationRecipientType } from './entities/notification.entity';

@Controller('notifications')
@UseGuards(JwtAuthGuard, RolesGuard)
export class NotificationController {
  constructor(private readonly notificationService: NotificationService) {}

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
    return this.notificationService.listUnread(
      recipientType,
      user.sub,
      query.page,
      query.limit,
    );
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
  async markAsRead(@Param('id') notificationId: string) {
    await this.notificationService.markAsRead(notificationId);
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

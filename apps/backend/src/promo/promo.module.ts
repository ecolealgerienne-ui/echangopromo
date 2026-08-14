import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuditLogModule } from '../audit-log/audit-log.module';
import { AuthModule } from '../auth/auth.module';
import { CommercantModule } from '../commercant/commercant.module';
import { NotificationModule } from '../notification/notification.module';
import { StorageModule } from '../storage/storage.module';
import { PromoController } from './promo.controller';
import { PromoService } from './promo.service';
import { PromoView } from './entities/promo-view.entity';
import { Promo } from './entities/promo.entity';

@Module({
  imports: [
    TypeOrmModule.forFeature([Promo, PromoView]),
    AuthModule,
    CommercantModule,
    StorageModule,
    // `AgentModule` retiré le 2026-08-13 : plus aucun consommateur dans
    // `promo/` une fois les gardes de commune supprimées (règle #31).
    NotificationModule,
    // ⚠️ Ajouté le 2026-08-13. `promo.controller.ts` invoquait un « canal
    // audité » depuis le 2026-07-14 pour justifier ses exemptions de plafond,
    // sans que ce module soit importé nulle part dans `promo/` (règle #11).
    AuditLogModule,
  ],
  controllers: [PromoController],
  providers: [PromoService],
  exports: [PromoService],
})
export class PromoModule {}

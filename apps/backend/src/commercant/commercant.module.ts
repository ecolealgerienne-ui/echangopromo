import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { NotificationModule } from '../notification/notification.module';
import { Promo } from '../promo/entities/promo.entity';
import { StorageModule } from '../storage/storage.module';
import { CommercantController } from './commercant.controller';
import { CommercantService } from './commercant.service';
import { CommercantView } from './entities/commercant-view.entity';
import { Commercant } from './entities/commercant.entity';

@Module({
  imports: [
    // Accès direct à l'entité Promo (pas au PromoModule, qui importe déjà
    // CommercantModule — cycle sinon) pour la cascade de statut posée par
    // `CommercantService.suspend`/`deleteCommercant`/`deleteAccount` (même
    // pattern que ReportModule pour la même raison, voir report.module.ts).
    TypeOrmModule.forFeature([Commercant, CommercantView, Promo]),
    AuthModule,
    StorageModule,
    NotificationModule,
  ],
  controllers: [CommercantController],
  providers: [CommercantService],
  exports: [CommercantService],
})
export class CommercantModule {}

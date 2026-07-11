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

import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentModule } from '../agent/agent.module';
import { AuthModule } from '../auth/auth.module';
import { CommercantModule } from '../commercant/commercant.module';
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
    AgentModule,
  ],
  controllers: [PromoController],
  providers: [PromoService],
  exports: [PromoService],
})
export class PromoModule {}

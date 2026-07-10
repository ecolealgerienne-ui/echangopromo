import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AgentModule } from '../agent/agent.module';
import { AuditLogModule } from '../audit-log/audit-log.module';
import { AuthModule } from '../auth/auth.module';
import { CommercantModule } from '../commercant/commercant.module';
import { PromoModule } from '../promo/promo.module';
import { ReportModule } from '../report/report.module';
import { StorageModule } from '../storage/storage.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { Admin } from './entities/admin.entity';
import { ModerationService } from './moderation.service';

@Module({
  imports: [
    TypeOrmModule.forFeature([Admin]),
    AuthModule,
    AgentModule,
    CommercantModule,
    PromoModule,
    ReportModule,
    AuditLogModule,
    StorageModule,
  ],
  controllers: [AdminController],
  providers: [AdminService, ModerationService],
  exports: [AdminService],
})
export class AdminModule {}

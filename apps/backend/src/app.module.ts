import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { CommuneModule } from './commune/commune.module';
import { ZoneModule } from './zone/zone.module';
import { CommercantModule } from './commercant/commercant.module';
import { PromoModule } from './promo/promo.module';
import { AgentModule } from './agent/agent.module';
import { AdminModule } from './admin/admin.module';
import { ReportModule } from './report/report.module';
import { AuditLogModule } from './audit-log/audit-log.module';
import { StorageModule } from './storage/storage.module';
import { AuthModule } from './auth/auth.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRoot({
      type: 'postgres',
      url: process.env.DATABASE_URL,
      autoLoadEntities: true,
      synchronize: process.env.NODE_ENV !== 'production',
    }),
    ScheduleModule.forRoot(),
    CommuneModule,
    ZoneModule,
    CommercantModule,
    PromoModule,
    AgentModule,
    AdminModule,
    ReportModule,
    AuditLogModule,
    StorageModule,
    AuthModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}

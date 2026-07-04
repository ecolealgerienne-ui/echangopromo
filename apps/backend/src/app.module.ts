import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
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
    // Limite globale par défaut ; les endpoints sensibles (login, OTP,
    // signalement) ont une limite plus stricte via @Throttle() (specs
    // d'audit sécurité — @nestjs/throttler n'était pas installé du tout).
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
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
  providers: [AppService, { provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}

import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { TypeOrmModule } from '@nestjs/typeorm';
import { CommuneModule } from './commune/commune.module';
import { CommercantModule } from './commercant/commercant.module';
import { PromoModule } from './promo/promo.module';
import { AgentModule } from './agent/agent.module';
import { AdminModule } from './admin/admin.module';
import { ReportModule } from './report/report.module';
import { AuditLogModule } from './audit-log/audit-log.module';
import { StorageModule } from './storage/storage.module';
import { AuthModule } from './auth/auth.module';
import { AppLinksModule } from './app-links/app-links.module';
import { validateEnv } from './config/env.validation';
import { typeOrmBaseOptions } from './data-source';

@Module({
  imports: [
    // `validate` fait échouer le démarrage si JWT_SECRET est absent ou
    // laissé à sa valeur par défaut — voir env.validation.ts.
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    /**
     * `synchronize` toujours false (voir data-source.ts) — le schéma est
     * géré exclusivement par des migrations versionnées (`npm run
     * migration:run`), plus par une bascule implicite sur NODE_ENV qui
     * rendait le déploiement Docker fragile ou dangereux selon le .env
     * monté (audit §2 — un volume neuf avec NODE_ENV=production ne créait
     * aucune table, et l'inverse activait synchronize sur un volume
     * persistant nommé "production").
     */
    TypeOrmModule.forRoot({
      ...typeOrmBaseOptions,
      autoLoadEntities: true,
    }),
    ScheduleModule.forRoot(),
    // Limite globale par défaut ; les endpoints sensibles (login, claim
    // commerçant, signalement) ont une limite plus stricte via @Throttle()
    // (specs d'audit sécurité — @nestjs/throttler n'était pas installé du tout).
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    // AppLinksController (App Links/Universal Links, host
    // 'promo.echango.com') utilise des chemins dédiés (`/p/:id`,
    // `.well-known/*`) qui ne recoupent jamais ceux de PromoController
    // (`/promo/:id`) — aucune dépendance à l'ordre d'enregistrement des
    // modules ici, contrairement à un chemin partagé.
    AppLinksModule,
    CommuneModule,
    CommercantModule,
    PromoModule,
    AgentModule,
    AdminModule,
    ReportModule,
    AuditLogModule,
    StorageModule,
    AuthModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}

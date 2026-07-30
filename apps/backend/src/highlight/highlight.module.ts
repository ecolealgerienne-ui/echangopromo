import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuditLogModule } from '../audit-log/audit-log.module';
import { AuthModule } from '../auth/auth.module';
import { PromoModule } from '../promo/promo.module';
import { StorageModule } from '../storage/storage.module';
import { AdminHighlightController } from './admin-highlight.controller';
import { Highlight } from './entities/highlight.entity';
import { HighlightController } from './highlight.controller';
import { HighlightService } from './highlight.service';

/**
 * `PromoModule` importé en entier (pas `TypeOrmModule.forFeature([Promo])`)
 * : ce module a besoin de la *règle* « qu'est-ce qu'une promo visible »,
 * qui vit dans `PromoService` et ne doit pas être réécrite ici (CLAUDE.md
 * #9). Aucun cycle — `PromoModule` n'a jamais connaissance de celui-ci.
 *
 * `AuditLogModule` branché dès ce premier commit, pas « plus tard » : la
 * curation du bandeau d'accueil est exactement le genre d'action admin que
 * ce module doit tracer (CLAUDE.md #11).
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([Highlight]),
    AuthModule,
    PromoModule,
    StorageModule,
    AuditLogModule,
  ],
  controllers: [HighlightController, AdminHighlightController],
  providers: [HighlightService],
  exports: [HighlightService],
})
export class HighlightModule {}

import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthModule } from '../auth/auth.module';
import { Commercant } from '../commercant/entities/commercant.entity';
import { CrmController } from './crm.controller';
import { CrmExportService } from './crm-export.service';

/**
 * L'alimentation du CRM Odoo — `docs/SPEC_INTEGRATION_ECHANGOCRM.md`.
 *
 * ⚠️ **Accès direct à l'entité `Commercant`** (`TypeOrmModule.forFeature`)
 * plutôt qu'un import de `CommercantModule` : ce module ne lit que des
 * agrégats en SQL brut et n'appelle aucune règle métier du service. Importer
 * le module entier créerait une dépendance dont rien n'est utilisé, et un
 * cycle le jour où `CommercantModule` voudrait lire l'export (règle #9).
 */
@Module({
  imports: [TypeOrmModule.forFeature([Commercant]), AuthModule],
  controllers: [CrmController],
  providers: [CrmExportService],
  exports: [CrmExportService],
})
export class CrmModule {}

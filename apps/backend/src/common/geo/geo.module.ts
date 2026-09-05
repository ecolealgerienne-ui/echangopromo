import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Commercant } from '../../commercant/entities/commercant.entity';
import { GeoClientService } from './geo-client.service';
import { GeoReconcileService } from './geo-reconcile.service';

/**
 * Le géocodage inverse via `echango-geo`.
 *
 * `GeoClientService` est exporté (injecté dans `CommercantService.setPosition`) ;
 * `GeoReconcileService` porte son `@Cron` et n'a pas besoin d'être exporté.
 * Accès direct à l'entité `Commercant` (comme `CrmModule`) plutôt qu'un import
 * de `CommercantModule` — cycle sinon, puisque `CommercantModule` importe
 * celui-ci.
 */
@Module({
  imports: [TypeOrmModule.forFeature([Commercant])],
  providers: [GeoClientService, GeoReconcileService],
  exports: [GeoClientService],
})
export class GeoModule {}

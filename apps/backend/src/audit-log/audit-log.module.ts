import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Admin } from '../admin/entities/admin.entity';
import { Agent } from '../agent/entities/agent.entity';
import { Commercant } from '../commercant/entities/commercant.entity';
import { Promo } from '../promo/entities/promo.entity';
import { AuditLogService } from './audit-log.service';
import { AuditLog } from './entities/audit-log.entity';

/**
 * ⚠️ **Quatre entités d'autres modules déclarées ici en direct** (règle 9), et
 * non leurs modules : `AdminModule`, `AgentModule`, `CommercantModule` et
 * `PromoModule` importent tous `AuditLogModule` pour écrire dans le journal —
 * les importer en retour créerait quatre cycles NestJS.
 *
 * L'accès est en **lecture seule** et sert uniquement à remplacer un UUID par
 * un libellé (`AuditLogService.resoudreLibelles`). Aucune règle métier de ces
 * modules n'est reproduite ici ; le seul écart assumé est de ne PAS filtrer les
 * comptes supprimés, parce qu'un journal qui perd le nom d'un commerçant le
 * jour où on le supprime perd sa valeur exactement quand elle compte.
 */
@Module({
  imports: [
    TypeOrmModule.forFeature([AuditLog, Agent, Admin, Commercant, Promo]),
  ],
  providers: [AuditLogService],
  exports: [AuditLogService],
})
export class AuditLogModule {}

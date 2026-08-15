import { Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { CrmExportService } from './crm-export.service';
import { CrmPushService } from './crm-push.service';

/**
 * La fenêtre de diagnostic sur l'export CRM.
 *
 * ⚠️ **Elle existe pour que le premier passage réel ne soit pas le premier
 * test.** Sans elle, la seule façon de voir ce que la requête rend serait
 * d'attendre 04:00 — et de lire le résultat dans Odoo, c'est-à-dire à travers
 * un second système qui peut lui aussi se tromper.
 *
 * ⚠️ **Réservée à l'admin**, et ce n'est pas un excès de prudence : cette route
 * sert le téléphone, la position et l'état de compte de TOUT le parc en une
 * requête. C'est le point le plus dense en données personnelles de tout le
 * produit (règle #33 — une route qu'on oublie de garder est ouverte).
 */
@Controller('crm')
export class CrmController {
  constructor(
    private readonly exportService: CrmExportService,
    private readonly pushService: CrmPushService,
  ) {}

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('merchants')
  async merchants(@Query() query: PaginationQueryDto) {
    const page = (query.page ?? 1) - 1;
    const taille = query.limit ?? 50;
    const [lot, total] = await Promise.all([
      this.exportService.lire(page, taille),
      this.exportService.compter(),
    ]);
    return {
      genere_le: new Date().toISOString(),
      total_attendu: total,
      page: page + 1,
      // ⚠️ Rendu à CHAQUE appel, pas seulement en test : c'est ce qui fait de
      // l'équivalence entre le SQL et la table un contrôle exécuté plutôt
      // qu'une intention (règle #30).
      equivalence: this.exportService.verifierEquivalence(lot.lignes, lot.brut),
      items: lot.lignes,
    };
  }

  /**
   * Déclenche l'envoi sans attendre 04:00.
   *
   * ⚠️ **Existe pour que le premier envoi réel ne soit pas le premier test.**
   * Il fait exactement ce que fait la tâche planifiée — même code, même lot,
   * même acquittement : un déclencheur qui emprunterait un autre chemin ne
   * prouverait rien de celui qui tourne la nuit.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('sync')
  async sync() {
    const resultat = await this.pushService.pousser();
    return (
      resultat ?? {
        envoye: false,
        raison: 'CRM_SYNC_URL / CRM_SYNC_TOKEN absents — rien n’a été envoyé',
      }
    );
  }
}

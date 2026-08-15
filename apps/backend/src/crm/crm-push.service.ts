import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron } from '@nestjs/schedule';
import { randomUUID } from 'crypto';
import { configNumber } from '../common/config/config-number';
import { CrmExportService, LigneCrm } from './crm-export.service';

/**
 * Pousse l'instantané nocturne vers le CRM Odoo.
 *
 * ── ⚠️ Sans jeton, il ne tourne pas — et c'est ce qui le rend inerte ────────
 *
 * Le lot 2 peut donc partir en production **avant** que le module Odoo
 * n'existe : sans `CRM_SYNC_TOKEN`, la tâche journalise son abstention et
 * s'arrête. Les deux autres possibilités seraient pires — pousser sans
 * authentification, ou échouer en silence chaque nuit (règle #29).
 *
 * ── ⚠️ Le fuseau est explicite, parce qu'aucune autre tâche ne l'était ─────
 *
 * `@Cron('0 4 * * *')` sans fuseau prend celui du **processus** : sur un VPS en
 * UTC, « 04:00 » se déclenche à 05:00 à Alger. Les quatre tâches existantes
 * vivent avec ce flou depuis toujours ; celle-ci le nomme plutôt que de le
 * subir, et `CRM_SYNC_TZ` permet d'en changer sans redéployer.
 *
 * ── ⚠️ Le lot est une unité, pas une suite de pages ────────────────────────
 *
 * Chaque envoi porte l'identifiant du passage et le **total attendu** ; la
 * dernière page est suivie d'un acquittement. Sans cela, Odoo ne peut pas
 * distinguer « ce commerçant n'est plus envoyé » de « l'export s'est arrêté à
 * la page 3 » — et sa règle d'archivage, qui repose sur l'absence,
 * archiverait tout le reste du parc.
 */
@Injectable()
export class CrmPushService {
  private readonly logger = new Logger(CrmPushService.name);

  constructor(
    private readonly exportService: CrmExportService,
    private readonly config: ConfigService,
  ) {}

  private url(): string {
    return (this.config.get<string>('CRM_SYNC_URL') ?? '').trim();
  }

  private jeton(): string {
    return (this.config.get<string>('CRM_SYNC_TOKEN') ?? '').trim();
  }

  private taillePage(): number {
    return configNumber(
      this.config.get('CRM_SYNC_PAGE_SIZE'),
      200,
      'CRM_SYNC_PAGE_SIZE',
    );
  }

  /**
   * 04:00, heure d'Alger par défaut.
   *
   * Les quatre tâches existantes occupent 01:00 (expiration), 02:00 (purge des
   * photos), 03:00 (purge des notifications) et 09:00 (relance avant
   * expiration). ⚠️ **04:00 tient pour la charge, pas pour l'ordre** :
   * `promos_en_ligne` porte déjà `dateFin > now()`, donc une promo expirée mais
   * pas encore basculée par la tâche de 01:00 n'est jamais comptée en ligne.
   */
  @Cron('0 4 * * *', { name: 'crm-sync', timeZone: 'Africa/Algiers' })
  async pousserCron(): Promise<void> {
    await this.pousser();
  }

  async pousser(): Promise<{
    envoyees: number;
    pages: number;
    lot: string;
  } | null> {
    const url = this.url();
    const jeton = this.jeton();
    if (!url || !jeton) {
      // Journalisé, jamais silencieux : une tâche qui ne fait rien sans le dire
      // est indiscernable d'une tâche qui échoue.
      this.logger.warn(
        'Export CRM non configuré (CRM_SYNC_URL / CRM_SYNC_TOKEN absents) — ' +
          'aucun envoi. Ce n’est pas une panne : le module Odoo peut ne pas ' +
          'encore exister.',
      );
      return null;
    }

    const lot = randomUUID();
    const taille = this.taillePage();
    const total = await this.exportService.compter();
    const pages = Math.max(1, Math.ceil(total / taille));
    this.logger.log(
      `Export CRM ${lot} — ${total} fiche(s), ${pages} page(s) de ${taille}`,
    );

    let envoyees = 0;
    for (let page = 0; page < pages; page++) {
      const { lignes, brut } = await this.exportService.lire(page, taille);
      // ⚠️ **Le contrôle d'équivalence tourne sur CHAQUE page envoyée**, pas
      // seulement dans la fenêtre de diagnostic. Une divergence entre le SQL et
      // la table des motifs ferait annoncer au CRM « peut publier » sur des
      // commerçants que le serveur refuse : on l'envoie quand même — le CRM a
      // besoin du lot — mais on le DIT, fort, à l'endroit où quelqu'un lit.
      const equiv = this.exportService.verifierEquivalence(lignes, brut);
      if (equiv.divergences.length > 0) {
        this.logger.error(
          `Export CRM ${lot} page ${page + 1} : ${equiv.divergences.length} ` +
            `divergence(s) entre le SQL et la table des motifs — ` +
            equiv.divergences.slice(0, 5).join(' ; '),
        );
      }

      await this.envoyer('/echango_promo/merchants/sync', jeton, url, {
        lot,
        genere_le: new Date().toISOString(),
        total_attendu: total,
        page: page + 1,
        pages,
        items: lignes,
      });
      envoyees += lignes.length;
    }

    // L'acquittement de fin : c'est LUI qui autorise Odoo à archiver ce qui
    // n'est plus envoyé. Sans lui, un export interrompu à la page 3 ferait
    // archiver tout le reste du parc.
    await this.envoyer('/echango_promo/merchants/ack', jeton, url, {
      lot,
      total_envoye: envoyees,
      total_attendu: total,
    });

    this.logger.log(`Export CRM ${lot} — ${envoyees} fiche(s) acquittée(s)`);
    return { envoyees, pages, lot };
  }

  private async envoyer(
    chemin: string,
    jeton: string,
    base: string,
    charge: Record<string, unknown> | { items: LigneCrm[] },
  ): Promise<void> {
    const reponse = await fetch(base.replace(/\/$/, '') + chemin, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Echango-Token': jeton,
      },
      body: JSON.stringify(charge),
      signal: AbortSignal.timeout(60_000),
    });
    if (!reponse.ok) {
      const corps = await reponse.text().catch(() => '');
      throw new Error(
        `CRM a refusé ${chemin} : HTTP ${reponse.status} ${corps.slice(0, 300)}`,
      );
    }
  }
}

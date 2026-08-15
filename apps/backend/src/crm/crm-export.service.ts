import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Commercant } from '../commercant/entities/commercant.entity';
import {
  MotifBlocagePublication,
  REGLES_PUBLICATION,
} from '../commercant/publication-eligibility';
import { configNumber } from '../common/config/config-number';
import { VISIBLE_MODERATION_STATUSES } from '../promo/entities/promo.entity';

/**
 * La ligne servie au CRM pour un commerçant.
 *
 * ⚠️ **Les noms sont ceux du contrat** (`docs/SPEC_INTEGRATION_ECHANGOCRM.md`
 * §4.1), pas ceux des colonnes de la base. Le CRM lit un contrat ; il n'a pas à
 * connaître notre schéma, et nous n'avons pas à figer nos colonnes parce qu'il
 * les lit.
 */
export interface LigneCrm {
  promo_uuid: string;
  nom: string;
  adresse: string | null;
  categorie: string;
  telephone_e164: string;
  pays: string;
  latitude: number | null;
  longitude: number | null;
  origine: string;
  agent_createur_id: string | null;
  date_creation: string;
  suspendu_le: string | null;
  supprime_le: string | null;
  consentement_le: string | null;
  est_active: boolean;
  date_derniere_publication: string | null;
  promos_sans_publication: number;
  promos_deja_publiees: number;
  promos_en_ligne: number;
  promos_visibles: number;
  promos_publiees_30j: number;
  promos_masquees: number;
  signalements_90j: number;
  nouveaux_visiteurs_fiche_30j: number;
  nouveaux_visiteurs_promos_30j: number;
  plafond_effectif: number;
  plafond_propre: number | null;
  registre_statut: string | null;
  peut_publier: boolean;
  motif_blocage: MotifBlocagePublication | null;
}

/**
 * Produit l'instantané servi au CRM Odoo.
 *
 * ── ⚠️ Quatre agrégations, jamais une jointure plate ────────────────────────
 *
 * Une seule requête joignant `promo`, `promo_view`, `report` et
 * `commercant_view` **multiplie les lignes** : pour un commerçant à 20 promos ×
 * 400 vues × 3 signalements × 150 vues de fiche, ce sont 3,6 millions de lignes
 * avant agrégation, et **tous** les compteurs gonflés du produit des autres
 * branches.
 *
 * Ce qui rend le défaut vicieux : `MAX(publishedAt)` **survit** au fan-out.
 * `date_derniere_publication` — le champ le plus important du contrat — serait
 * le **seul juste** d'un lot entièrement faux. D'où quatre CTE groupées
 * chacune sur `commercantId`, puis des `LEFT JOIN`.
 *
 * ── ⚠️ Ce que cette requête recopie, et qu'elle ne devrait pas ─────────────
 *
 * `promos_visibles` exprime en SQL les conditions de visibilité que
 * `PromoService.applyVisibleConditions` porte en QueryBuilder. Les deux ne
 * peuvent pas partager de code — l'une construit un QueryBuilder, l'autre est
 * du SQL brut dans une CTE. C'est donc une **seconde écriture**, et le dépôt a
 * déjà produit trois copies partielles de cette règle.
 *
 * Ce qui la tient : la liste des statuts vient de la **constante partagée**
 * (`VISIBLE_MODERATION_STATUSES`), et le banc `test-crm-export.sh` compare, pour
 * chaque commerçant, `promos_visibles` au nombre réellement servi par l'API
 * publique. Une divergence y est visible, pas déductible.
 */
@Injectable()
export class CrmExportService {
  private readonly logger = new Logger(CrmExportService.name);

  constructor(
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    private readonly config: ConfigService,
  ) {}

  private plafondParDefaut(): number {
    return configNumber(
      this.config.get('PROMO_ACTIVE_CAP'),
      5,
      'PROMO_ACTIVE_CAP',
    );
  }

  private quotaCreationParDefaut(): number {
    return configNumber(
      this.config.get('PROMO_DAILY_CREATION_CAP'),
      5,
      'PROMO_DAILY_CREATION_CAP',
    );
  }

  /**
   * Le `CASE` des motifs, **construit depuis la table** et dans son ordre.
   *
   * ⚠️ Écrire ce `CASE` à la main ferait vivre l'ordre à deux endroits — et
   * l'ordre est signifiant : un commerçant suspendu **et** sans position doit
   * s'entendre dire qu'il est suspendu.
   */
  private casMotifs(): string {
    const branches = REGLES_PUBLICATION.map(
      (regle) => `WHEN (${regle.sql}) THEN '${regle.motif}'`,
    ).join('\n           ');
    return `CASE ${branches}\n           ELSE NULL\n         END`;
  }

  /**
   * L'instantané complet, page par page.
   *
   * ⚠️ **Un instantané, pas un incrémental.** `Commercant.updatedAt` ne bouge
   * ni à la publication d'une promo, ni à l'enregistrement d'une vue, ni à
   * l'arrivée d'un signalement — un curseur raterait donc exactement les fiches
   * dont les indicateurs ont changé (vérifié sur les trois chemins le
   * 2026-08-15).
   *
   * ⚠️ **Les supprimés restent servis 30 jours.** Une requête sans état ne sait
   * pas ce qu'elle a déjà envoyé : faire dépendre la propagation d'une
   * suppression de la réussite d'UNE nuit précise, c'est perdre en silence le
   * seul chemin par lequel un effacement (loi 18-07) atteint le CRM.
   */
  async lire(page: number, taille: number): Promise<LigneCrm[]> {
    const visibles = VISIBLE_MODERATION_STATUSES.map((s) => `'${s}'`).join(
      ', ',
    );

    const sql = `
      WITH promos AS (
        SELECT "commercantId" AS cid,
               COUNT(*) FILTER (WHERE "publishedAt" IS NOT NULL)::int AS deja_publiees,
               COUNT(*) FILTER (WHERE "publishedAt" IS NULL)::int      AS sans_publication,
               MAX("publishedAt")                                     AS derniere_publication,
               COUNT(*) FILTER (WHERE "lifecycleStatus" = 'publiee'
                                  AND "dateFin" > now())::int         AS en_ligne,
               -- Les cinq conditions de la visibilité client : statut éditorial,
               -- date de fin, modération, et les deux gardes de compte —
               -- celles-ci portées par la table \`commercant\` en dehors de la CTE.
               COUNT(*) FILTER (WHERE "lifecycleStatus" = 'publiee'
                                  AND "dateFin" > now()
                                  AND "moderationStatus" IN (${visibles}))::int AS visibles,
               COUNT(*) FILTER (WHERE "publishedAt" > now() - interval '30 days')::int AS publiees_30j,
               COUNT(*) FILTER (WHERE "moderationStatus" = 'masquee')::int      AS masquees,
               COUNT(*) FILTER (WHERE "createdAt" > now() - interval '24 hours')::int AS creations_24h
          FROM promo
         GROUP BY "commercantId"
      ),
      vues_promo AS (
        SELECT p."commercantId" AS cid, COUNT(*)::int AS n
          FROM promo_view v
          JOIN promo p ON p.id = v."promoId"
         WHERE v."createdAt" > now() - interval '30 days'
         GROUP BY p."commercantId"
      ),
      vues_fiche AS (
        SELECT "commercantId" AS cid, COUNT(*)::int AS n
          FROM commercant_view
         WHERE "createdAt" > now() - interval '30 days'
         GROUP BY "commercantId"
      ),
      signalements AS (
        SELECT p."commercantId" AS cid, COUNT(*)::int AS n
          FROM report r
          JOIN promo p ON p.id = r."promoId"
         WHERE r."createdAt" > now() - interval '90 days'
         GROUP BY p."commercantId"
      ),
      agrege AS (
        SELECT f.id,
               COALESCE(pr.en_ligne, 0)                        AS promos_en_ligne,
               COALESCE(f."promoActiveCap", $1)                 AS plafond_effectif,
               COALESCE(pr.creations_24h, 0)                    AS creations_24h,
               $2::int                                          AS quota_creation_24h
          FROM commercant f
          LEFT JOIN promos pr ON pr.cid = f.id
      )
      SELECT f.id                                   AS promo_uuid,
             f.nom,
             f.adresse,
             f.categorie,
             f.telephone                            AS telephone_e164,
             f.pays,
             f.latitude, f.longitude,
             f."originVerification"                 AS origine,
             f."createdByAgentId"                   AS agent_createur_id,
             f."createdAt"                          AS date_creation,
             f."suspendedAt"                        AS suspendu_le,
             f."deletedAt"                          AS supprime_le,
             f."consentedAt"                        AS consentement_le,
             f."registreStatus"                     AS registre_statut,
             f."promoActiveCap"                     AS plafond_propre,
             a.plafond_effectif::int                AS plafond_effectif,
             (COALESCE(pr.deja_publiees, 0) > 0)    AS est_active,
             pr.derniere_publication                AS date_derniere_publication,
             COALESCE(pr.sans_publication, 0)       AS promos_sans_publication,
             COALESCE(pr.deja_publiees, 0)          AS promos_deja_publiees,
             a.promos_en_ligne,
             COALESCE(pr.visibles, 0)               AS promos_visibles,
             COALESCE(pr.publiees_30j, 0)           AS promos_publiees_30j,
             COALESCE(pr.masquees, 0)               AS promos_masquees,
             COALESCE(sg.n, 0)                      AS signalements_90j,
             COALESCE(vf.n, 0)                      AS nouveaux_visiteurs_fiche_30j,
             COALESCE(vp.n, 0)                      AS nouveaux_visiteurs_promos_30j,
             a.creations_24h,
             a.quota_creation_24h,
             ${this.casMotifs()}                    AS motif_blocage
        FROM commercant f
        JOIN agrege a       ON a.id = f.id
        LEFT JOIN promos pr ON pr.cid = f.id
        LEFT JOIN vues_promo vp ON vp.cid = f.id
        LEFT JOIN vues_fiche vf ON vf.cid = f.id
        LEFT JOIN signalements sg ON sg.cid = f.id
       WHERE f."deletedAt" IS NULL
          OR f."deletedAt" > now() - interval '30 days'
       ORDER BY f."createdAt" ASC, f.id ASC
       LIMIT $3 OFFSET $4
    `;

    // `query()` rend déjà `any[]` : l'assertion serait retirée par le lint.
    const brut: Record<string, unknown>[] = await this.commercants.query(sql, [
      this.plafondParDefaut(),
      this.quotaCreationParDefaut(),
      taille,
      page * taille,
    ]);

    return brut.map((l) => this.enLigneCrm(l));
  }

  /** Combien de fiches le lot entier contiendra — l'en-tête l'annonce. */
  async compter(): Promise<number> {
    const r: { n: number }[] = await this.commercants.query(
      `SELECT COUNT(*)::int AS n FROM commercant
        WHERE "deletedAt" IS NULL OR "deletedAt" > now() - interval '30 days'`,
    );
    return r[0]?.n ?? 0;
  }

  private enLigneCrm(l: Record<string, unknown>): LigneCrm {
    const motif = (l.motif_blocage as MotifBlocagePublication | null) ?? null;
    const date = (v: unknown): string | null =>
      v instanceof Date ? v.toISOString() : (v as string | null);
    const nombre = (v: unknown): number => Number(v ?? 0);
    return {
      promo_uuid: l.promo_uuid as string,
      nom: l.nom as string,
      adresse: (l.adresse as string) ?? null,
      categorie: l.categorie as string,
      telephone_e164: l.telephone_e164 as string,
      pays: l.pays as string,
      latitude: l.latitude === null ? null : Number(l.latitude),
      longitude: l.longitude === null ? null : Number(l.longitude),
      origine: l.origine as string,
      agent_createur_id: (l.agent_createur_id as string) ?? null,
      date_creation: date(l.date_creation) as string,
      suspendu_le: date(l.suspendu_le),
      supprime_le: date(l.supprime_le),
      consentement_le: date(l.consentement_le),
      est_active: l.est_active === true,
      date_derniere_publication: date(l.date_derniere_publication),
      promos_sans_publication: nombre(l.promos_sans_publication),
      promos_deja_publiees: nombre(l.promos_deja_publiees),
      promos_en_ligne: nombre(l.promos_en_ligne),
      promos_visibles: nombre(l.promos_visibles),
      promos_publiees_30j: nombre(l.promos_publiees_30j),
      promos_masquees: nombre(l.promos_masquees),
      signalements_90j: nombre(l.signalements_90j),
      nouveaux_visiteurs_fiche_30j: nombre(l.nouveaux_visiteurs_fiche_30j),
      nouveaux_visiteurs_promos_30j: nombre(l.nouveaux_visiteurs_promos_30j),
      plafond_effectif: nombre(l.plafond_effectif),
      plafond_propre:
        l.plafond_propre === null ? null : nombre(l.plafond_propre),
      registre_statut: (l.registre_statut as string) ?? null,
      peut_publier: motif === null,
      motif_blocage: motif,
    };
  }
}

import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Plafond de promos actives **par commerçant**, facultatif.
 *
 * ── Pourquoi une colonne nullable, et pas un défaut à 5 ─────────────────────
 *
 * `NULL` veut dire « suit le réglage global » (`PROMO_ACTIVE_CAP`), ce
 * qu'aucune valeur numérique ne sait exprimer. Poser `DEFAULT 5` figerait
 * chaque commerçant existant à 5 : le jour où le global passerait à 8,
 * personne n'en profiterait, et rien ne le signalerait. C'est la règle #29 —
 * un défaut n'a pas de valeur par défaut, l'absence est une information.
 *
 * ── Ce que cette migration ne fait PAS ──────────────────────────────────────
 *
 * Aucun `UPDATE` : tous les commerçants restent à `NULL`, donc au réglage
 * global. La colonne ne change rien tant qu'un admin ne la remplit pas —
 * `PATCH /admin/commercant/:id/plafond-promos`.
 *
 * Pas d'index non plus, et c'est délibéré (règle #12, prise à l'envers) : la
 * colonne n'est jamais un critère de filtre ni de jointure, seulement une
 * lecture sur une ligne déjà chargée par son id.
 */
export class AddCommercantPromoActiveCap1783850000000 implements MigrationInterface {
  name = 'AddCommercantPromoActiveCap1783850000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD "promoActiveCap" integer`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP COLUMN "promoActiveCap"`,
    );
  }
}

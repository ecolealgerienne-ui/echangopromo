import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Aligne les noms de contraintes et d'index sur ceux que TypeORM calcule.
 *
 * ── Pourquoi cette migration existe ─────────────────────────────────────────
 *
 * `migration:generate` rendait dix opérations à chaque appel, sur un schéma
 * pourtant à jour. Elles étaient sans danger — chaque `DROP` avait sa
 * recréation dans le même `up()` — mais elles n'étaient pas *sans effet* :
 * c'est ce bruit-là qui a caché un `DROP INDEX "UQ_commercant_telephone_active"`
 * SANS recréation (voir `docs/status_v0.1.md`, P10). Un diff qu'on sait devoir
 * ignorer est un diff qu'on ne lit plus, et c'est la onzième ligne qui coûte.
 *
 * ── Pourquoi dans CE sens ───────────────────────────────────────────────────
 *
 * L'inverse — garder `FK_agent_communes_agent`, lisible, et l'imposer à
 * TypeORM — n'est faisable qu'à moitié : `@JoinTable` accepte bien un
 * `foreignKeyConstraintName` pour ses deux clés étrangères, mais les deux
 * INDEX qu'il pose sur les colonnes de jointure ne sont pas nommables (leur
 * nom vient de la stratégie de nommage, pas du décorateur). On silencierait
 * 4 opérations sur 10 et le bruit resterait — donc on plie la base, une fois.
 *
 * Les noms en `IDX_78055ba…` / `FK_2200ad7…` sont laids mais DÉTERMINISTES :
 * TypeORM les dérive du nom de table et des colonnes. Ils ne changeront pas
 * tant que la table et ses colonnes ne changent pas.
 *
 * ⚠️ Vérifié avant d'écrire : aucun de ces noms n'apparaît ailleurs que dans
 * les migrations — ni dans le code applicatif, ni dans les scripts, ni dans
 * les bancs. Rien ne s'y réfère, rien ne casse.
 *
 * ── Une ligne qui N'EST PAS un renommage ────────────────────────────────────
 *
 * Les deux clés étrangères de `agent_communes` passent de
 * `ON UPDATE NO ACTION` à `ON UPDATE CASCADE`. C'est le défaut de TypeORM
 * pour une table de jointure, et c'est le seul vrai changement de
 * comportement du lot. Il est inerte en pratique — les deux clés référencées
 * sont des UUID générés qui ne sont jamais mis à jour — et il va dans le sens
 * sûr : si l'un d'eux changeait un jour, les lignes de jointure suivraient au
 * lieu de faire échouer la mise à jour.
 *
 * Elle est écrite ici parce qu'elle était précisément invisible dans le lot :
 * dix lignes qu'on appelle « des renommages » en contenaient une qui n'en
 * était pas.
 *
 * ── Ce qui atteste que ça a marché ──────────────────────────────────────────
 *
 * Un `migration:generate` qui ne rend plus RIEN après application. C'est le
 * seul verdict qui compte : tant qu'il rend quelque chose, l'entité et la
 * base ne disent pas la même chose.
 */
export class AlignConstraintNamesWithTypeorm1783840000000 implements MigrationInterface {
  name = 'AlignConstraintNamesWithTypeorm1783840000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "highlight" DROP CONSTRAINT "FK_highlight_promo"`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" DROP CONSTRAINT "FK_agent_communes_agent"`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" DROP CONSTRAINT "FK_agent_communes_commune"`,
    );
    await queryRunner.query(`DROP INDEX "public"."IDX_agent_communes_agentId"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_agent_communes_communeId"`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_78055ba28315617b9907074a04" ON "agent_communes" ("agentId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_2200ad7268d75025aff78530d3" ON "agent_communes" ("communeId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "highlight" ADD CONSTRAINT "FK_3b7a6274b9dcc2af9a934eea367" ` +
        `FOREIGN KEY ("promoId") REFERENCES "promo"("id") ` +
        `ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_78055ba28315617b9907074a046" ` +
        `FOREIGN KEY ("agentId") REFERENCES "agent"("id") ` +
        `ON DELETE CASCADE ON UPDATE CASCADE`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_2200ad7268d75025aff78530d36" ` +
        `FOREIGN KEY ("communeId") REFERENCES "commune"("id") ` +
        `ON DELETE CASCADE ON UPDATE CASCADE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "agent_communes" DROP CONSTRAINT "FK_2200ad7268d75025aff78530d36"`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" DROP CONSTRAINT "FK_78055ba28315617b9907074a046"`,
    );
    await queryRunner.query(
      `ALTER TABLE "highlight" DROP CONSTRAINT "FK_3b7a6274b9dcc2af9a934eea367"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_2200ad7268d75025aff78530d3"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_78055ba28315617b9907074a04"`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_agent_communes_communeId" ON "agent_communes" ("communeId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_agent_communes_agentId" ON "agent_communes" ("agentId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_agent_communes_commune" ` +
        `FOREIGN KEY ("communeId") REFERENCES "commune"("id") ` +
        `ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_agent_communes_agent" ` +
        `FOREIGN KEY ("agentId") REFERENCES "agent"("id") ` +
        `ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "highlight" ADD CONSTRAINT "FK_highlight_promo" ` +
        `FOREIGN KEY ("promoId") REFERENCES "promo"("id") ` +
        `ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
  }
}

import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Abandon du concept de Zone opérationnelle (pivot produit — un agent doit
 * pouvoir couvrir plusieurs communes, voire une wilaya entière, le staffing
 * "un agent par commune" n'étant pas soutenable). Remplacé par une relation
 * many-to-many `Agent <-> Commune` (`agent_communes`) ; `commercant.zoneId`
 * était de toute façon redondant avec `commercant.communeId`, déjà la
 * référence utilisée pour le filtrage/IDOR.
 *
 * Pas de migration de données : les assignations zone->agent existantes ne
 * peuvent pas être déduites automatiquement en assignations commune->agent
 * (une Zone ne correspondait à aucune Commune précise, specs §5.2) — à
 * refaire manuellement côté admin après déploiement.
 */
export class RemoveZoneAddAgentCommunes1783670000000
  implements MigrationInterface
{
  name = 'RemoveZoneAddAgentCommunes1783670000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "agent" DROP CONSTRAINT "FK_4b95070f5da52e73191397b519a"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_4b95070f5da52e73191397b519"`,
    );
    await queryRunner.query(`ALTER TABLE "agent" DROP COLUMN "zoneId"`);

    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "FK_64db32f863983ab6b527aacce10"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_64db32f863983ab6b527aacce1"`,
    );
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "zoneId"`);

    await queryRunner.query(`DROP TABLE "zone"`);

    await queryRunner.query(
      `CREATE TABLE "agent_communes" ("agentId" uuid NOT NULL, "communeId" uuid NOT NULL, CONSTRAINT "PK_agent_communes" PRIMARY KEY ("agentId", "communeId"))`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_agent_communes_agentId" ON "agent_communes" ("agentId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_agent_communes_communeId" ON "agent_communes" ("communeId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_agent_communes_agent" FOREIGN KEY ("agentId") REFERENCES "agent"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent_communes" ADD CONSTRAINT "FK_agent_communes_commune" FOREIGN KEY ("communeId") REFERENCES "commune"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "agent_communes"`);

    await queryRunner.query(
      `CREATE TABLE "zone" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "nom" character varying NOT NULL, "description" text, CONSTRAINT "PK_bd3989e5a3c3fb5ed546dfaf832" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(`ALTER TABLE "agent" ADD "zoneId" uuid`);
    await queryRunner.query(
      `CREATE INDEX "IDX_4b95070f5da52e73191397b519" ON "agent" ("zoneId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent" ADD CONSTRAINT "FK_4b95070f5da52e73191397b519a" FOREIGN KEY ("zoneId") REFERENCES "zone"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );

    await queryRunner.query(`ALTER TABLE "commercant" ADD "zoneId" uuid`);
    await queryRunner.query(
      `CREATE INDEX "IDX_64db32f863983ab6b527aacce1" ON "commercant" ("zoneId")`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "FK_64db32f863983ab6b527aacce10" FOREIGN KEY ("zoneId") REFERENCES "zone"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
  }
}

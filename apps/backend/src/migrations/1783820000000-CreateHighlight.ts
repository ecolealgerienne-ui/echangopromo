import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Bandeau « Top promos » de l'accueil curé par l'admin (voir
 * `highlight.entity.ts`). Purement additif : tant qu'aucune ligne n'existe,
 * `GET /highlight` retombe sur le classement calculé (« meilleures
 * réductions »), qui est exactement le comportement d'avant cette table.
 *
 * `ON DELETE SET NULL` sur la promo ciblée, jamais `CASCADE` : une promo
 * disparue ne doit pas effacer silencieusement une diapositive composée par
 * l'admin (titre, image importée) — elle reste visible et corrigeable côté
 * admin, simplement masquée côté client.
 */
export class CreateHighlight1783820000000 implements MigrationInterface {
  name = 'CreateHighlight1783820000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "highlight" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "position" integer NOT NULL DEFAULT 0,
        "active" boolean NOT NULL DEFAULT true,
        "promoId" uuid,
        "imageKey" character varying,
        "titre" character varying(60),
        "sousTitre" character varying(100),
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_highlight" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(
      `ALTER TABLE "highlight" ADD CONSTRAINT "FK_highlight_promo" ` +
        `FOREIGN KEY ("promoId") REFERENCES "promo"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
    // PostgreSQL n'indexe pas automatiquement une clé étrangère (CLAUDE.md
    // #12) — cette colonne sert de jointure à chaque chargement.
    await queryRunner.query(
      `CREATE INDEX "IDX_highlight_promo" ON "highlight" ("promoId")`,
    );
    // Requête de l'accueil : actives, triées par position.
    await queryRunner.query(
      `CREATE INDEX "IDX_highlight_active_position" ON "highlight" ("active", "position")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "highlight"`);
  }
}

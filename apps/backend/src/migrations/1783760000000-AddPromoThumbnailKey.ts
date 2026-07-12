import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Miniature générée côté serveur pour la 1ère photo d'une promo
 * (décision produit 2026-07-12) — colonne nullable, `null` tant qu'aucune
 * miniature n'a été (re)générée (promos existantes, ou échec best-effort).
 */
export class AddPromoThumbnailKey1783760000000 implements MigrationInterface {
  name = 'AddPromoThumbnailKey1783760000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "promo" ADD "thumbnailKey" character varying`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "promo" DROP COLUMN "thumbnailKey"`);
  }
}

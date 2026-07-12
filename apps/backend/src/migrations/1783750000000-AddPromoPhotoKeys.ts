import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Multi-photo promo (décision produit 2026-07-12, jusqu'à 3 photos) :
 * `photoKey` (une seule clé S3) devient `photoKeys` (tableau ordonné, 1 à 3
 * éléments). Migration des données existantes plutôt qu'un ajout à vide —
 * chaque promo déjà en base garde sa photo unique comme premier élément.
 */
export class AddPromoPhotoKeys1783750000000 implements MigrationInterface {
  name = 'AddPromoPhotoKeys1783750000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "promo" ADD "photoKeys" text[] NOT NULL DEFAULT '{}'`,
    );
    await queryRunner.query(`UPDATE "promo" SET "photoKeys" = ARRAY["photoKey"]`);
    await queryRunner.query(`ALTER TABLE "promo" DROP COLUMN "photoKey"`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "promo" ADD "photoKey" character varying`);
    await queryRunner.query(`UPDATE "promo" SET "photoKey" = "photoKeys"[1]`);
    await queryRunner.query(`ALTER TABLE "promo" ALTER COLUMN "photoKey" SET NOT NULL`);
    await queryRunner.query(`ALTER TABLE "promo" DROP COLUMN "photoKeys"`);
  }
}

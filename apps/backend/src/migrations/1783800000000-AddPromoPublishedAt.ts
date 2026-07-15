import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `createdAt` ne suffit pas pour trier "nouveautés" côté client : il ne
 * bouge pas si la promo a d'abord été créée en brouillon puis publiée plus
 * tard, et `updatedAt` est écrasé par toute modification ultérieure
 * (retour terrain 2026-07-14). `publishedAt` est posé/rafraîchi uniquement
 * par `PromoService.publish()` (et la création directe en publiée).
 */
export class AddPromoPublishedAt1783800000000 implements MigrationInterface {
  name = 'AddPromoPublishedAt1783800000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "promo" ADD "publishedAt" TIMESTAMP WITH TIME ZONE`,
    );
    // Backfill best-effort pour les promos déjà publiées avant l'ajout de
    // cette colonne — updatedAt reste la meilleure approximation disponible
    // pour les lignes existantes (pas d'historique exact).
    await queryRunner.query(
      `UPDATE "promo" SET "publishedAt" = "updatedAt" WHERE "lifecycleStatus" != 'brouillon'`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "promo" DROP COLUMN "publishedAt"`);
  }
}

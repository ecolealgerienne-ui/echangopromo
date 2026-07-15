import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Statut de cycle de vie dédié à la cascade de suppression de compte
 * commerçant (`CommercantService.deleteAccount`/`deleteCommercant`,
 * 2026-07-14) — distinct d'`ARRETEE` (arrêt volontaire d'une promo, compte
 * toujours actif).
 */
export class AddPromoLifecycleSupprimee1783790000000 implements MigrationInterface {
  name = 'AddPromoLifecycleSupprimee1783790000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "public"."promo_lifecyclestatus_enum" ADD VALUE 'supprimee'`,
    );
  }

  public async down(): Promise<void> {
    // Postgres ne supporte pas de retirer une valeur d'un type enum — pas
    // de rollback possible sans recréer le type (même limitation acceptée
    // que les migrations équivalentes ailleurs dans ce projet).
  }
}

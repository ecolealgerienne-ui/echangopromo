import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddPromoExpiringSoonNotificationType1783700000000
  implements MigrationInterface
{
  name = 'AddPromoExpiringSoonNotificationType1783700000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "public"."notification_type_enum" ADD VALUE 'promo_expiring_soon'`,
    );
  }

  public async down(): Promise<void> {
    // Postgres ne supporte pas de retirer une valeur d'un type enum — pas
    // de rollback possible sans recréer le type (voir migrations
    // équivalentes ailleurs dans ce projet, même limitation acceptée).
  }
}

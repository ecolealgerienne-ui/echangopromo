import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddProfileValidatedNotificationType1783740000000
  implements MigrationInterface
{
  name = 'AddProfileValidatedNotificationType1783740000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "public"."notification_type_enum" ADD VALUE 'profile_validated'`,
    );
  }

  public async down(): Promise<void> {
    // Postgres ne supporte pas de retirer une valeur d'un type enum — pas
    // de rollback possible sans recréer le type (même limitation acceptée
    // que les migrations équivalentes ailleurs dans ce projet).
  }
}

import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `NotificationType.REGISTRE_VALIDATED`/`.REGISTRE_REJECTED` (ajoutés au
 * flux de validation du registre de commerce, 2026-07-11) n'avaient jamais
 * reçu leur migration — l'enum TypeScript avait changé mais pas le type
 * Postgres (`synchronize: false` toujours, aucune bascule automatique).
 * Sans cette migration, la première validation/rejet de registre en
 * production aurait fait planter `NotificationService.create` avec
 * `invalid input value for enum notification_type_enum`.
 */
export class AddRegistreNotificationTypes1783720000000
  implements MigrationInterface
{
  name = 'AddRegistreNotificationTypes1783720000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TYPE "public"."notification_type_enum" ADD VALUE 'registre_validated'`,
    );
    await queryRunner.query(
      `ALTER TYPE "public"."notification_type_enum" ADD VALUE 'registre_rejected'`,
    );
  }

  public async down(): Promise<void> {
    // Postgres ne supporte pas de retirer une valeur d'un type enum — pas
    // de rollback possible sans recréer le type (même limitation acceptée
    // que les migrations équivalentes ailleurs dans ce projet).
  }
}

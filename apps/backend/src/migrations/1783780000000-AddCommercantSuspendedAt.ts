import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Sépare la suspension (réversible, arbitraire) de la suppression
 * (`deletedAt`, logique mais définitive, libère le numéro de téléphone) —
 * les deux partageaient `deletedAt` jusqu'ici, ce qui libérait par erreur le
 * numéro de téléphone dès qu'un admin suspendait un compte (bug trouvé
 * 2026-07-14).
 */
export class AddCommercantSuspendedAt1783780000000 implements MigrationInterface {
  name = 'AddCommercantSuspendedAt1783780000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD "suspendedAt" TIMESTAMP WITH TIME ZONE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "suspendedAt"`);
  }
}

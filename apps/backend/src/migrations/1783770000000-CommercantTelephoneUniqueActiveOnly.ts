import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `telephone` était unique parmi TOUTES les lignes, y compris les
 * commerçants suspendus (soft delete, `deletedAt` non nul) — un numéro
 * suspendu restait donc bloqué indéfiniment, impossible à réattribuer au
 * vrai propriétaire en cas de changement de main du commerce (bug trouvé
 * 2026-07-13). Remplacé par un index unique partiel, actif uniquement
 * parmi les comptes non supprimés.
 */
export class CommercantTelephoneUniqueActiveOnly1783770000000
  implements MigrationInterface
{
  name = 'CommercantTelephoneUniqueActiveOnly1783770000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "UQ_a2964b0e4b92eb96e4458d1721b"`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_commercant_telephone_active" ON "commercant" ("telephone") WHERE "deletedAt" IS NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "UQ_commercant_telephone_active"`);
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "UQ_a2964b0e4b92eb96e4458d1721b" UNIQUE ("telephone")`,
    );
  }
}

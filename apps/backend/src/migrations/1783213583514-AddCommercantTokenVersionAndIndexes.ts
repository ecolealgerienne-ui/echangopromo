import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddCommercantTokenVersionAndIndexes1783213583514 implements MigrationInterface {
  name = 'AddCommercantTokenVersionAndIndexes1783213583514';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "admin" ADD "tokenVersion" integer NOT NULL DEFAULT '0'`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent" ADD "tokenVersion" integer NOT NULL DEFAULT '0'`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD "tokenVersion" integer NOT NULL DEFAULT '0'`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_4b95070f5da52e73191397b519" ON "agent"  ("zoneId") `,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_3a4e57ba870f67f7e0d6893154" ON "commercant"  ("createdByAgentId") `,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `DROP INDEX "public"."IDX_3a4e57ba870f67f7e0d6893154"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_4b95070f5da52e73191397b519"`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP COLUMN "tokenVersion"`,
    );
    await queryRunner.query(`ALTER TABLE "agent" DROP COLUMN "tokenVersion"`);
    await queryRunner.query(`ALTER TABLE "admin" DROP COLUMN "tokenVersion"`);
  }
}

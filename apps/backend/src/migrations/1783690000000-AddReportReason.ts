import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddReportReason1783690000000 implements MigrationInterface {
  name = 'AddReportReason1783690000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TYPE "public"."report_reason_enum" AS ENUM('perime', 'arnaque', 'photo_trompeuse', 'autre')`,
    );
    await queryRunner.query(
      `ALTER TABLE "report" ADD "reason" "public"."report_reason_enum"`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "report" DROP COLUMN "reason"`);
    await queryRunner.query(`DROP TYPE "public"."report_reason_enum"`);
  }
}

import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddCommercantDeletedAt1783650000000 implements MigrationInterface {
  name = 'AddCommercantDeletedAt1783650000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD "deletedAt" TIMESTAMP WITH TIME ZONE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "deletedAt"`);
  }
}

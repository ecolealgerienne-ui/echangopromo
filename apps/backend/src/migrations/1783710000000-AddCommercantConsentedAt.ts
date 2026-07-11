import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddCommercantConsentedAt1783710000000 implements MigrationInterface {
  name = 'AddCommercantConsentedAt1783710000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD "consentedAt" TIMESTAMP WITH TIME ZONE`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "consentedAt"`);
  }
}

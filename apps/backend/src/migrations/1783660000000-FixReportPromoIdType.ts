import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `report.promoId` était `character varying` (défaut TypeORM pour un
 * `string` sans `type` explicite) alors que `promo.id` est `uuid` — une
 * jointure SQL directe entre les deux (file de modération admin) échoue
 * avec `operator does not exist: uuid = character varying`. Toutes les
 * valeurs existantes sont garanties des UUID valides (`CreateReportDto`
 * impose `@IsUUID()` à la création), le cast est donc sûr.
 */
export class FixReportPromoIdType1783660000000 implements MigrationInterface {
  name = 'FixReportPromoIdType1783660000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "report" ALTER COLUMN "promoId" TYPE uuid USING "promoId"::uuid`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "report" ALTER COLUMN "promoId" TYPE character varying USING "promoId"::character varying`,
    );
  }
}

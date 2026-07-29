import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * L'écran carte filtre les commerçants sur une zone visible
 * (`latitude BETWEEN ... AND longitude BETWEEN ...`, voir
 * `PromoService.findActiveForMap`) : sans index, chaque déplacement de la
 * carte déclenche un parcours complet de la table.
 *
 * Index partiel : seuls les commerçants ayant renseigné leur position sont
 * concernés par cette requête (la position est facultative à l'inscription),
 * ce qui garde l'index plus petit que la table.
 *
 * Purement additif — aucune donnée modifiée, aucune contrainte ajoutée.
 */
export class AddCommercantPositionIndex1783810000000 implements MigrationInterface {
  name = 'AddCommercantPositionIndex1783810000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE INDEX "IDX_commercant_position" ON "commercant" ("latitude", "longitude") ` +
        `WHERE "latitude" IS NOT NULL AND "longitude" IS NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "IDX_commercant_position"`);
  }
}

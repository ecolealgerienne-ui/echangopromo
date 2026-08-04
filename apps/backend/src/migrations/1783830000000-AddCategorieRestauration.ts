import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Ajoute la catégorie « restauration » (specs §5.6, décision produit
 * 2026-07-30) — restaurants, fast-foods, salons de thé.
 *
 * Deux tables portent cet enum, chacune avec son propre type PostgreSQL :
 * `commercant.categorie` et `promo.categorie`. Les deux doivent être
 * migrées, sinon un commerce peut se déclarer restaurant sans pouvoir
 * publier une promo dans cette catégorie.
 *
 * Le type est **recréé** plutôt qu'étendu par `ALTER TYPE ... ADD VALUE` :
 * cette commande ne s'exécute pas dans un bloc transactionnel avant
 * PostgreSQL 12, or TypeORM enveloppe chaque migration dans une
 * transaction. La recréation, elle, fonctionne sur toutes les versions.
 * Aucune donnée n'est touchée — la conversion se fait par la valeur
 * textuelle, identique de part et d'autre.
 *
 * La nouvelle valeur est insérée après `alimentation` : l'ordre du type
 * reflète l'ordre d'affichage côté mobile.
 */
const OLD_VALUES = `'alimentation', 'vetements_textile', 'electromenager', 'beaute_hygiene', 'maison_ameublement', 'autre'`;
const NEW_VALUES = `'alimentation', 'restauration', 'vetements_textile', 'electromenager', 'beaute_hygiene', 'maison_ameublement', 'autre'`;

/** `[type PostgreSQL, table]` — même traitement des deux côtés. */
const TARGETS: readonly [string, string][] = [
  ['commercant_categorie_enum', 'commercant'],
  ['promo_categorie_enum', 'promo'],
];

export class AddCategorieRestauration1783830000000 implements MigrationInterface {
  name = 'AddCategorieRestauration1783830000000';

  private async replaceEnum(
    queryRunner: QueryRunner,
    values: string,
  ): Promise<void> {
    for (const [type, table] of TARGETS) {
      await queryRunner.query(
        `ALTER TYPE "public"."${type}" RENAME TO "${type}_old"`,
      );
      await queryRunner.query(
        `CREATE TYPE "public"."${type}" AS ENUM(${values})`,
      );
      await queryRunner.query(
        `ALTER TABLE "${table}" ALTER COLUMN "categorie" TYPE "public"."${type}" ` +
          `USING "categorie"::text::"public"."${type}"`,
      );
      await queryRunner.query(`DROP TYPE "public"."${type}_old"`);
    }
  }

  public async up(queryRunner: QueryRunner): Promise<void> {
    await this.replaceEnum(queryRunner, NEW_VALUES);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // Les lignes déjà classées en `restauration` n'auraient plus de valeur
    // valide : les ramener sur `autre` avant de restreindre le type, sinon
    // la conversion échoue et le retour arrière est impossible.
    for (const [, table] of TARGETS) {
      await queryRunner.query(
        `UPDATE "${table}" SET "categorie" = 'autre' WHERE "categorie" = 'restauration'`,
      );
    }
    await this.replaceEnum(queryRunner, OLD_VALUES);
  }
}

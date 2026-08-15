import { MigrationInterface, QueryRunner } from 'typeorm';
import { normaliserTelephone, PAYS_PAR_DEFAUT } from '../commercant/telephone';

/**
 * Ajoute le pays du numéro, et **normalise ce qui est déjà en base**.
 *
 * ⚠️ **La colonne n'est pas le correctif ; la normalisation l'est.** Les DTO
 * portaient `@IsPhoneNumber('DZ')`, qui accepte indifféremment `0555000101` et
 * `+213555000101`, et rien ne normalisait avant l'écriture — alors que l'app
 * affiche `+213...` en exemple de saisie. Les deux formes sont deux chaînes
 * distinctes : l'index unique ne les rapproche pas, et la recherche par numéro
 * ne trouve que la forme exacte utilisée à l'inscription. Conséquences déjà
 * possibles aujourd'hui : **deux comptes actifs pour un même commerçant**, et
 * une connexion refusée à qui saisit l'autre forme que la sienne.
 *
 * ── Ordre des opérations, et pourquoi celui-là ────────────────────────────
 *
 * 1. **L'index unique est retiré d'abord.** Normaliser peut rendre identiques
 *    deux lignes qui ne l'étaient pas : l'`UPDATE` heurterait l'ancien index et
 *    ferait échouer la migration sur un message d'unicité incompréhensible.
 * 2. **La normalisation, ligne par ligne**, avec la même fonction que le
 *    service — pas une réécriture SQL de la règle (règle #30).
 * 3. **La détection des collisions**, avant de reposer l'unicité. Une collision
 *    est un vrai doublon qu'il faut arbitrer à la main : garder l'un ou l'autre
 *    est une décision produit, jamais celle d'une migration. On lève, la
 *    transaction annule tout, et le message nomme les numéros en cause.
 * 4. **L'index composite `(pays, telephone)`**, sous le **même nom** que
 *    l'ancien : `CommercantService.saveNewAccount` traduit le `23505` de cette
 *    contrainte — et d'elle seule — en « numéro déjà pris ». Le renommer aurait
 *    rendu ce refus métier en `500`.
 *
 * Un numéro qui ne se laisse pas normaliser (saisie ancienne, aberrante) est
 * **laissé tel quel** et journalisé : le supprimer ou le deviner ferait perdre
 * le seul identifiant de connexion d'un commerçant. Il restera introuvable au
 * login exactement comme avant cette migration — pas mieux, pas pire — et la
 * liste imprimée dit lesquels reprendre à la main.
 */
export class AddCommercantPaysAndNormalizePhones1783890000000 implements MigrationInterface {
  name = 'AddCommercantPaysAndNormalizePhones1783890000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD COLUMN "pays" character varying(2) NOT NULL DEFAULT '${PAYS_PAR_DEFAUT}'`,
    );

    await queryRunner.query(`DROP INDEX "UQ_commercant_telephone_active"`);

    const lignes = (await queryRunner.query(
      `SELECT "id", "telephone", "deletedAt" FROM "commercant"`,
    )) as { id: string; telephone: string; deletedAt: Date | null }[];

    const illisibles: string[] = [];
    for (const ligne of lignes) {
      const normalise = normaliserTelephone(ligne.telephone, PAYS_PAR_DEFAUT);
      if (!normalise) {
        illisibles.push(`${ligne.id} (${ligne.telephone})`);
        continue;
      }
      if (normalise.national !== ligne.telephone) {
        await queryRunner.query(
          `UPDATE "commercant" SET "telephone" = $1 WHERE "id" = $2`,
          [normalise.national, ligne.id],
        );
      }
    }

    if (illisibles.length > 0) {
      // Journalisé, pas levé : ces lignes étaient déjà inutilisables avant.
      console.warn(
        `[migration] ${illisibles.length} numéro(s) non normalisables, laissés tels quels : ${illisibles.join(', ')}`,
      );
    }

    const collisions = (await queryRunner.query(
      `SELECT "pays", "telephone", COUNT(*)::int AS n
         FROM "commercant"
        WHERE "deletedAt" IS NULL
        GROUP BY "pays", "telephone"
       HAVING COUNT(*) > 1`,
    )) as { pays: string; telephone: string; n: number }[];

    if (collisions.length > 0) {
      const detail = collisions
        .map((c) => `${c.pays} ${c.telephone} (${c.n} comptes actifs)`)
        .join(', ');
      throw new Error(
        `Normalisation impossible : ${collisions.length} numéro(s) portent plusieurs comptes actifs une fois normalisés — ${detail}. ` +
          `Arbitrer ces doublons à la main (supprimer ou fusionner) puis relancer la migration.`,
      );
    }

    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_commercant_telephone_active" ON "commercant" ("pays", "telephone") WHERE "deletedAt" IS NULL`,
    );
  }

  /**
   * ⚠️ **Le `down` ne restaure pas les formes d'origine** — elles ne sont
   * enregistrées nulle part, et les inventer serait pire que l'absence. Il
   * revient à l'unicité sur le seul numéro et retire la colonne ; les numéros
   * restent sous leur forme nationale, ce qui est la forme correcte.
   */
  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "UQ_commercant_telephone_active"`);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_commercant_telephone_active" ON "commercant" ("telephone") WHERE "deletedAt" IS NULL`,
    );
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "pays"`);
  }
}

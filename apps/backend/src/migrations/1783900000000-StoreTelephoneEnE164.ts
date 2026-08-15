import { MigrationInterface, QueryRunner } from 'typeorm';
import { normaliserTelephone, PAYS_PAR_DEFAUT } from '../commercant/telephone';

/**
 * Bascule la forme **stockée** du téléphone en E.164 : `0555000101` devient
 * `+213555000101`.
 *
 * ── Pourquoi une seconde migration ────────────────────────────────────────
 *
 * `1783890000000` a normalisé le parc vers la forme **nationale**, et elle est
 * déjà appliquée sur l'environnement de développement. La réécrire pour qu'elle
 * produise directement l'E.164 ne changerait rien là où elle a déjà tourné, et
 * ferait diverger deux bases qui ont vu deux versions du même fichier. Une
 * migration appliquée ne se modifie pas ; on en écrit une seconde.
 *
 * Sur un environnement neuf — le VPS — les deux s'enchaînent dans l'ordre et
 * aboutissent au même état.
 *
 * ── Ce que la conversion ne peut pas casser ───────────────────────────────
 *
 * Elle est **bijective à pays constant** : deux numéros nationaux distincts
 * d'un même pays donnent deux E.164 distincts. L'unicité `(pays, telephone)` ne
 * peut donc pas être violée par la conversion elle-même. Le contrôle est fait
 * quand même, parce qu'un raisonnement juste sur des données supposées propres
 * ne dit rien des données réelles — et qu'une garde qui ne coûte rien vaut
 * mieux qu'une certitude.
 *
 * ⚠️ **Un numéro illisible est laissé tel quel et journalisé.** Le supprimer ou
 * le deviner ferait perdre à un commerçant son seul identifiant de connexion.
 */
export class StoreTelephoneEnE1641783900000000 implements MigrationInterface {
  name = 'StoreTelephoneEnE1641783900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const lignes = (await queryRunner.query(
      `SELECT "id", "telephone", "pays" FROM "commercant"`,
    )) as { id: string; telephone: string; pays: string | null }[];

    const illisibles: string[] = [];
    for (const ligne of lignes) {
      const pays = (ligne.pays || PAYS_PAR_DEFAUT) as 'DZ';
      const normalise = normaliserTelephone(ligne.telephone, pays);
      if (!normalise) {
        illisibles.push(`${ligne.id} (${ligne.telephone})`);
        continue;
      }
      if (normalise.e164 !== ligne.telephone) {
        await queryRunner.query(
          `UPDATE "commercant" SET "telephone" = $1 WHERE "id" = $2`,
          [normalise.e164, ligne.id],
        );
      }
    }

    if (illisibles.length > 0) {
      console.warn(
        `[migration] ${illisibles.length} numéro(s) non convertibles, laissés tels quels : ${illisibles.join(', ')}`,
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
        `Conversion E.164 impossible : ${collisions.length} numéro(s) portent plusieurs comptes actifs — ${detail}. ` +
          `Arbitrer ces doublons à la main puis relancer.`,
      );
    }
  }

  /** Retour à la forme nationale, celle que `1783890000000` avait posée. */
  public async down(queryRunner: QueryRunner): Promise<void> {
    const lignes = (await queryRunner.query(
      `SELECT "id", "telephone", "pays" FROM "commercant"`,
    )) as { id: string; telephone: string; pays: string | null }[];

    for (const ligne of lignes) {
      const pays = (ligne.pays || PAYS_PAR_DEFAUT) as 'DZ';
      const normalise = normaliserTelephone(ligne.telephone, pays);
      if (normalise && normalise.national !== ligne.telephone) {
        await queryRunner.query(
          `UPDATE "commercant" SET "telephone" = $1 WHERE "id" = $2`,
          [normalise.national, ligne.id],
        );
      }
    }
  }
}

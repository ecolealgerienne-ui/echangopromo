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
 *
 * ⚠️ **Ce fichier a été modifié APRÈS avoir été appliqué en développement**, ce
 * que le paragraphe ci-dessus interdit — et la nuance vaut d'être dite. La
 * correction ne touche que le **chemin d'échec** (où la détection de collision
 * se place) : l'état produit par un `up()` réussi est identique au caractère
 * près, donc aucune base ne peut diverger d'une autre. La seule alternative
 * aurait été de laisser partir en production une garde incapable de se
 * déclencher.
 */
export class StoreTelephoneEnE1641783900000000 implements MigrationInterface {
  name = 'StoreTelephoneEnE1641783900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    const lignes = (await queryRunner.query(
      `SELECT "id", "telephone", "pays", "deletedAt" FROM "commercant"`,
    )) as {
      id: string;
      telephone: string;
      pays: string | null;
      deletedAt: Date | null;
    }[];

    // ⚠️ **La détection AVANT la première écriture, et c'est un correctif.**
    // Elle était placée après la boucle d'`UPDATE`, comme dans la migration
    // précédente — sauf que celle-là **retire l'index unique** avant de
    // convertir, ce que celle-ci ne fait pas. Le premier `UPDATE` créant un
    // doublon heurtait donc l'index et faisait échouer la migration sur
    // « duplicate key value violates unique constraint », **avant** que la
    // garde n'ait la moindre chance de parler.
    //
    // La transaction annulait bien tout — la sécurité tenait — mais le message
    // ne nommait aucun numéro, et c'était toute la raison d'être de cette
    // garde : dire lesquels arbitrer. Mesuré le 2026-08-15 en fabriquant le
    // doublon exprès ; sans ce test, une garde morte serait partie en
    // production avec l'air de protéger quelque chose (règle #28).
    const projections = new Map<string, string[]>();
    for (const ligne of lignes) {
      if (ligne.deletedAt) continue;
      const pays = (ligne.pays || PAYS_PAR_DEFAUT) as 'DZ';
      const cible = normaliserTelephone(ligne.telephone, pays);
      if (!cible) continue;
      const clef = `${pays} ${cible.e164}`;
      projections.set(clef, [
        ...(projections.get(clef) ?? []),
        ligne.telephone,
      ]);
    }
    const collisions = [...projections.entries()].filter(
      ([, formes]) => formes.length > 1,
    );
    if (collisions.length > 0) {
      const detail = collisions
        .map(([clef, formes]) => `${clef} ← ${formes.join(' + ')}`)
        .join(', ');
      throw new Error(
        `Conversion E.164 impossible : ${collisions.length} numéro(s) porteraient plusieurs comptes actifs — ${detail}. ` +
          `Arbitrer ces doublons à la main (supprimer ou fusionner) puis relancer.`,
      );
    }

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

    // La vérification d'après-coup a été retirée : elle ne pouvait plus rien
    // dire que la projection ci-dessus n'ait déjà dit, et la garder aurait
    // laissé croire à deux filets là où il n'y en a qu'un.
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

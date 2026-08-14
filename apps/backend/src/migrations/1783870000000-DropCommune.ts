import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Suppression du découpage administratif — seconde et dernière moitié du
 * chantier ouvert par `MakeCommercantCommuneNullable`.
 *
 * ── ⚠️ NON RÉVERSIBLE, et il faut le lire avant de lancer ───────────────────
 *
 * `down()` est vide **par honnêteté**, pas par paresse. Recréer les tables ne
 * rendrait pas leur contenu, et recréer `commercant."communeId" NOT NULL` sur
 * des lignes existantes exigerait une valeur inventée pour tout commerçant
 * inscrit après ce chantier. Un `down()` qui reconstruit une coquille vide est
 * pire qu'un `down()` absent : il laisse croire qu'on peut revenir.
 *
 * **Sauvegarde prise avant exécution** (2026-08-13, hors dépôt) : un `pg_dump`
 * des deux tables et un export CSV de la correspondance commerçant ↔ commune,
 * avec nom et wilaya. C'est le seul filet, et il est volontairement en dehors
 * du dépôt — cette donnée n'a pas à être versionnée.
 *
 * ── Ce que cette migration NE fait PAS, et c'est une décision ───────────────
 *
 * **Aucune recopie de `« commune, wilaya »` vers `adresse`.** Elle était prévue,
 * puis abandonnée le 2026-08-13 après que deux revues adverses en ont chiffré
 * le prix.
 *
 * Ce qu'elle aurait protégé : **22 fiches** sans adresse et rattachées à une
 * commune, sur une base de **développement** — rien n'est publié.
 *
 * Ce qu'elle aurait coûté, sur un champ que les CGU font certifier « exact » au
 * commerçant et que la politique de confidentialité déclare « public par
 * nature » :
 * - une adresse **fabriquée montrée aux clients** sur la fiche promo
 *   (« Djelfa, Djelfa » pour la première ligne du parc) ;
 * - un **re-blocage de publication** dès qu'il la corrige (tout `PATCH
 *   /commercant/me` pose `profilePendingReview`) ;
 * - l'**impossibilité de l'effacer** : l'app n'envoie pas un champ vide, on ne
 *   peut que remplacer.
 *
 * Le texte recopié serait par ailleurs venu d'un référentiel dont l'en-tête du
 * seed avertissait lui-même qu'il n'avait pas été vérifié, et dont trois
 * documents du dépôt donnaient trois décomptes différents.
 *
 * ── L'ordre, et ce qui casse si on l'inverse ────────────────────────────────
 *
 * 1. `agent_communes` — table de liaison. Emporte ses deux index et ses deux
 *    clés étrangères. **Doit précéder** le `DROP TABLE commune`, sinon Postgres
 *    refuse (`cannot drop table commune because other objects depend on it`)
 *    et la transaction entière échoue — TypeORM enveloppant toutes les
 *    migrations en attente dans une seule, un lot légitime appliqué dans le
 *    même `run` serait annulé avec.
 * 2. `commercant."communeId"` — la colonne emporte son index. Sa contrainte de
 *    clé étrangère est déjà partie avec `MakeCommercantCommuneNullable`, quand
 *    la relation a quitté l'entité.
 * 3. `commune` — le référentiel, désormais sans référent.
 */
export class DropCommune1783870000000 implements MigrationInterface {
  name = 'DropCommune1783870000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "agent_communes"`);
    await queryRunner.query(`ALTER TABLE "commercant" DROP COLUMN "communeId"`);
    await queryRunner.query(`DROP TABLE "commune"`);
  }

  // eslint-disable-next-line @typescript-eslint/require-await
  public async down(): Promise<void> {
    throw new Error(
      'DropCommune1783870000000 est non réversible : les tables et la colonne ' +
        'ont été détruites avec leur contenu. Une sauvegarde hors dépôt a été ' +
        'prise le 2026-08-13 (pg_dump des deux tables + export CSV de la ' +
        'correspondance commerçant ↔ commune) ; la restauration se fait ' +
        'depuis elle, à la main, pas par ce down().',
    );
  }
}

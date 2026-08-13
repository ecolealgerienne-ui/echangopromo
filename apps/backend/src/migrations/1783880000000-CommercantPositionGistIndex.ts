import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Passe l'index de position d'un **btree à deux colonnes** à un **GiST sur une
 * expression de point** — décision produit du 2026-08-13, prise sur mesure.
 *
 * ── Ce qui a été mesuré, et qui l'a motivée ───────────────────────────────
 *
 * Un btree `(latitude, longitude)` ne restreint que sur sa **première**
 * colonne : la longitude n'est qu'un filtre appliqué après coup, à l'intérieur
 * de l'index. Sur un cadre de 5 km autour de Djelfa, mesuré par
 * `test-plan-sql.sh` :
 *
 *     btree (latitude, longitude)          101 lignes remontées
 *     gist  (point(longitude, latitude))    53 lignes remontées   ← les justes
 *
 * 48 lignes lues puis jetées à chaque requête de carte ou de liste. Invisible à
 * 154 commerçants ; structurel dès qu'une bande de latitude cesse d'être un
 * quartier — au niveau national, une bande traversant l'Algérie contiendrait
 * une grande part du parc.
 *
 * ── ⚠️ Pas de PostGIS, et c'est délibéré ──────────────────────────────────
 *
 * Le type `point` et l'opérateur `<@` (contenu dans une boîte) sont **natifs**
 * dans PostgreSQL, avec un opclass GiST fourni en standard. Installer PostGIS
 * pour une recherche par cadre ajouterait une extension à provisionner sur
 * chaque environnement, sans rien apporter ici : la distance exacte reste
 * calculée en haversine par `PromoService`, comme avant.
 *
 * ── ⚠️ L'ordre des coordonnées est INVERSÉ, et c'est une source d'erreur ──
 *
 * `point(x, y)` attend x **puis** y, soit `point(longitude, latitude)` — alors
 * que tout le reste du produit dit « lat, lng ». Un index construit sur
 * `point(latitude, longitude)` et interrogé par une boîte `(lng, lat)` ne
 * rendrait pas d'erreur : il rendrait des **résultats faux**, silencieusement,
 * et seulement pour les points où l'inversion sort du cadre. La requête de
 * `PromoService.applyBoundingBox` respecte le même ordre, et
 * `test-plan-sql.sh` compare le nombre de lignes servies à celui de l'API —
 * une inversion y ferait diverger les deux totaux.
 *
 * ── Ce que cette migration ne change pas ──────────────────────────────────
 *
 * Aucune donnée, aucune contrainte, aucune colonne. Le prédicat partiel est
 * conservé à l'identique : seuls les commerçants ayant renseigné leur position
 * entrent dans l'index, qui reste plus petit que la table.
 *
 * ⚠️ Le `down()` remet exactement le btree d'origine, tel que
 * `1783810000000-AddCommercantPositionIndex` l'avait posé — un retour arrière
 * qui laisserait la base dans un troisième état ne serait pas un retour arrière.
 */
export class CommercantPositionGistIndex1783880000000 implements MigrationInterface {
  name = 'CommercantPositionGistIndex1783880000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "IDX_commercant_position"`);
    await queryRunner.query(
      `CREATE INDEX "IDX_commercant_position" ON "commercant" ` +
        `USING gist (point("longitude", "latitude")) ` +
        `WHERE "latitude" IS NOT NULL AND "longitude" IS NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "IDX_commercant_position"`);
    await queryRunner.query(
      `CREATE INDEX "IDX_commercant_position" ON "commercant" ("latitude", "longitude") ` +
        `WHERE "latitude" IS NOT NULL AND "longitude" IS NOT NULL`,
    );
  }
}

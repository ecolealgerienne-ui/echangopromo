import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * Ajoute le repère texte dérivé de la position — `ville`/`wilaya` géocodées —
 * et l'état de ce géocodage (specs `echango-geo` §8.3).
 *
 * ── Pourquoi ces colonnes vivent ici et pas dans le CRM ───────────────────
 *
 * Le CRM Odoo reverse-géocodait la position lui-même contre Nominatim (cron
 * 15 min, lots de 25, seuil de dérive, gestion du 429, 61 fiches perdues une
 * fois). Le commerçant appartient à CE produit : sa position est résolue
 * **ici**, une fois, au moment où elle est posée (`CommercantService`
 * `.setPosition` est le seul écrivain de `latitude`/`longitude`), via le
 * service transverse `echango-geo`. Le CRM se contente désormais de lire
 * `ville`/`wilaya` du snapshot.
 *
 * ── Backfill : tout ce qui a une position repart en `a_faire` ─────────────
 *
 * Les fiches déjà positionnées n'ont jamais été géocodées côté backend. Elles
 * passent en `a_faire` — `GeoReconcileService` les traite au prochain
 * passage, contre l'`echango-geo` local (pas de quota, pas de lot à calibrer :
 * quelques minutes pour le parc entier, contre ~3 h côté Nominatim public).
 * Les fiches sans position passent en `sans_position` : elles ne sont pas « à
 * faire », il n'y a rien à faire tant que le commerçant n'a pas posé de point.
 *
 * ── `down()` ─────────────────────────────────────────────────────────────
 *
 * Retire les colonnes, l'index et le type enum. Aucune donnée d'origine
 * touchée : `latitude`/`longitude` ne sont pas modifiés par cette migration.
 */
export class CommercantGeocodage1783910000000 implements MigrationInterface {
  name = 'CommercantGeocodage1783910000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TYPE "public"."commercant_geocodagestatut_enum" AS ENUM(` +
        `'sans_position', 'a_faire', 'fait', 'sans_resultat', 'erreur')`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ` +
        `ADD "geocodageStatut" "public"."commercant_geocodagestatut_enum" NOT NULL DEFAULT 'sans_position', ` +
        `ADD "villeGeocodee" character varying, ` +
        `ADD "wilayaGeocodee" character varying, ` +
        `ADD "geocodageLatitude" double precision, ` +
        `ADD "geocodageLongitude" double precision, ` +
        `ADD "geocodageAt" TIMESTAMP WITH TIME ZONE`,
    );
    await queryRunner.query(
      `UPDATE "commercant" SET "geocodageStatut" = CASE ` +
        `WHEN "latitude" IS NULL OR "longitude" IS NULL THEN 'sans_position' ` +
        `ELSE 'a_faire' END::"public"."commercant_geocodagestatut_enum"`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_commercant_geocodage_statut" ON "commercant" ("geocodageStatut")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_commercant_geocodage_statut"`);
    await queryRunner.query(
      `ALTER TABLE "commercant" ` +
        `DROP COLUMN "geocodageAt", ` +
        `DROP COLUMN "geocodageLongitude", ` +
        `DROP COLUMN "geocodageLatitude", ` +
        `DROP COLUMN "wilayaGeocodee", ` +
        `DROP COLUMN "villeGeocodee", ` +
        `DROP COLUMN "geocodageStatut"`,
    );
    await queryRunner.query(`DROP TYPE "public"."commercant_geocodagestatut_enum"`);
  }
}

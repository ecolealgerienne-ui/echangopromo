import { MigrationInterface, QueryRunner } from 'typeorm';

export class InitialSchema1783192047695 implements MigrationInterface {
  name = 'InitialSchema1783192047695';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `CREATE TABLE "admin" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "email" character varying NOT NULL, "passwordHash" character varying NOT NULL, "nom" character varying NOT NULL, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_de87485f6489f5d0995f5841952" UNIQUE ("email"), CONSTRAINT "PK_e032310bcef831fb83101899b10" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE TABLE "zone" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "nom" character varying NOT NULL, "description" text, CONSTRAINT "PK_bd3989e5a3c3fb5ed546dfaf832" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE TABLE "agent" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "email" character varying NOT NULL, "passwordHash" character varying NOT NULL, "nom" character varying NOT NULL, "zoneId" uuid, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_c8e51500f3876fa1bbd4483ecc1" UNIQUE ("email"), CONSTRAINT "PK_1000e989398c5d4ed585cf9a46f" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."audit_log_actortype_enum" AS ENUM('agent', 'admin')`,
    );
    await queryRunner.query(
      `CREATE TABLE "audit_log" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "actorType" "public"."audit_log_actortype_enum" NOT NULL, "actorId" character varying NOT NULL, "action" character varying NOT NULL, "targetType" character varying, "targetId" character varying, "metadata" jsonb, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_07fefa57f7f5ab8fc3f52b3ed0b" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE TABLE "commercant_view" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "commercantId" character varying NOT NULL, "deviceId" character varying NOT NULL, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_34021e8165879bd6a5779a38402" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_eabed0071bde485ad0a9fbad1e" ON "commercant_view"  ("commercantId", "deviceId") `,
    );
    await queryRunner.query(
      `CREATE TABLE "commune" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "wilaya" character varying NOT NULL, "nom" character varying NOT NULL, CONSTRAINT "PK_bc512eb8412b43c9dc6e2c9e683" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."commercant_categorie_enum" AS ENUM('alimentation', 'vetements_textile', 'electromenager', 'beaute_hygiene', 'maison_ameublement', 'autre')`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."commercant_accountstate_enum" AS ENUM('cree_agent', 'autonome')`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."commercant_originverification_enum" AS ENUM('auto_inscrit', 'confirme_agent')`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."commercant_registrestatus_enum" AS ENUM('en_attente', 'valide', 'rejete')`,
    );
    await queryRunner.query(
      `CREATE TABLE "commercant" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "telephone" character varying NOT NULL, "nom" character varying NOT NULL, "adresse" character varying, "categorie" "public"."commercant_categorie_enum" NOT NULL, "communeId" uuid NOT NULL, "zoneId" uuid, "createdByAgentId" uuid, "accountState" "public"."commercant_accountstate_enum" NOT NULL DEFAULT 'cree_agent', "originVerification" "public"."commercant_originverification_enum" NOT NULL, "pinHash" character varying, "photoKey" character varying, "latitude" double precision, "longitude" double precision, "registreStatus" "public"."commercant_registrestatus_enum", "registreKey" character varying, "registreValidatedAt" TIMESTAMP WITH TIME ZONE, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), "updatedAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_a2964b0e4b92eb96e4458d1721b" UNIQUE ("telephone"), CONSTRAINT "PK_5bcd7aaece4e6bee7503f75c529" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_c017a3a877de774baf103f4c0b" ON "commercant"  ("communeId") `,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_64db32f863983ab6b527aacce1" ON "commercant"  ("zoneId") `,
    );
    await queryRunner.query(
      `CREATE TABLE "promo_view" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "promoId" character varying NOT NULL, "deviceId" character varying NOT NULL, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_09fd737bbf4162d1bf0351e0b96" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_b4fdf3b8e41bb4ddb9b813a515" ON "promo_view"  ("promoId", "deviceId") `,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."promo_categorie_enum" AS ENUM('alimentation', 'vetements_textile', 'electromenager', 'beaute_hygiene', 'maison_ameublement', 'autre')`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."promo_lifecyclestatus_enum" AS ENUM('brouillon', 'publiee', 'arretee', 'expiree')`,
    );
    await queryRunner.query(
      `CREATE TYPE "public"."promo_moderationstatus_enum" AS ENUM('normale', 'signalee', 'masquee', 'verifiee_ok')`,
    );
    await queryRunner.query(
      `CREATE TABLE "promo" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "commercantId" uuid NOT NULL, "description" character varying(140) NOT NULL, "prixAvant" numeric(10,2) NOT NULL, "prixApres" numeric(10,2) NOT NULL, "categorie" "public"."promo_categorie_enum" NOT NULL, "photoKey" character varying NOT NULL, "dateFin" TIMESTAMP WITH TIME ZONE, "lifecycleStatus" "public"."promo_lifecyclestatus_enum" NOT NULL DEFAULT 'brouillon', "moderationStatus" "public"."promo_moderationstatus_enum" NOT NULL DEFAULT 'normale', "verifiedOkAt" TIMESTAMP WITH TIME ZONE, "photoPurgedAt" TIMESTAMP WITH TIME ZONE, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), "updatedAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_49d7e83df682fb7e87187e1c843" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_1cf5e216a24512b57e93210591" ON "promo"  ("commercantId") `,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_31e2d99143e9b234e1144ef623" ON "promo"  ("lifecycleStatus", "dateFin") `,
    );
    await queryRunner.query(
      `CREATE TABLE "report" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "promoId" character varying NOT NULL, "deviceId" character varying NOT NULL, "createdAt" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_99e4d0bea58cba73c57f935a546" PRIMARY KEY ("id"))`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "IDX_ca54780da5da761bcc0f3c04e9" ON "report"  ("promoId", "deviceId") `,
    );
    await queryRunner.query(
      `ALTER TABLE "agent" ADD CONSTRAINT "FK_4b95070f5da52e73191397b519a" FOREIGN KEY ("zoneId") REFERENCES "zone"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "FK_c017a3a877de774baf103f4c0b8" FOREIGN KEY ("communeId") REFERENCES "commune"("id") ON DELETE NO ACTION ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "FK_64db32f863983ab6b527aacce10" FOREIGN KEY ("zoneId") REFERENCES "zone"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "FK_3a4e57ba870f67f7e0d68931547" FOREIGN KEY ("createdByAgentId") REFERENCES "agent"("id") ON DELETE SET NULL ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "promo" ADD CONSTRAINT "FK_1cf5e216a24512b57e932105912" FOREIGN KEY ("commercantId") REFERENCES "commercant"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "promo" DROP CONSTRAINT "FK_1cf5e216a24512b57e932105912"`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "FK_3a4e57ba870f67f7e0d68931547"`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "FK_64db32f863983ab6b527aacce10"`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "FK_c017a3a877de774baf103f4c0b8"`,
    );
    await queryRunner.query(
      `ALTER TABLE "agent" DROP CONSTRAINT "FK_4b95070f5da52e73191397b519a"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_ca54780da5da761bcc0f3c04e9"`,
    );
    await queryRunner.query(`DROP TABLE "report"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_31e2d99143e9b234e1144ef623"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_1cf5e216a24512b57e93210591"`,
    );
    await queryRunner.query(`DROP TABLE "promo"`);
    await queryRunner.query(`DROP TYPE "public"."promo_moderationstatus_enum"`);
    await queryRunner.query(`DROP TYPE "public"."promo_lifecyclestatus_enum"`);
    await queryRunner.query(`DROP TYPE "public"."promo_categorie_enum"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_b4fdf3b8e41bb4ddb9b813a515"`,
    );
    await queryRunner.query(`DROP TABLE "promo_view"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_64db32f863983ab6b527aacce1"`,
    );
    await queryRunner.query(
      `DROP INDEX "public"."IDX_c017a3a877de774baf103f4c0b"`,
    );
    await queryRunner.query(`DROP TABLE "commercant"`);
    await queryRunner.query(
      `DROP TYPE "public"."commercant_registrestatus_enum"`,
    );
    await queryRunner.query(
      `DROP TYPE "public"."commercant_originverification_enum"`,
    );
    await queryRunner.query(
      `DROP TYPE "public"."commercant_accountstate_enum"`,
    );
    await queryRunner.query(`DROP TYPE "public"."commercant_categorie_enum"`);
    await queryRunner.query(`DROP TABLE "commune"`);
    await queryRunner.query(
      `DROP INDEX "public"."IDX_eabed0071bde485ad0a9fbad1e"`,
    );
    await queryRunner.query(`DROP TABLE "commercant_view"`);
    await queryRunner.query(`DROP TABLE "audit_log"`);
    await queryRunner.query(`DROP TYPE "public"."audit_log_actortype_enum"`);
    await queryRunner.query(`DROP TABLE "agent"`);
    await queryRunner.query(`DROP TABLE "zone"`);
    await queryRunner.query(`DROP TABLE "admin"`);
  }
}

import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * `commercant."communeId"` devient nullable — première moitié du chantier
 * « suppression de commune ». La seconde (recopie vers `adresse` puis `DROP`)
 * est une migration à part, au lot L7.
 *
 * ── Pourquoi ce n'est pas un assouplissement, mais une nécessité ────────────
 *
 * Le même lot retire `communeId` de `RegisterCommercantDto` et de
 * `CreateCommercantByAgentDto`, où il était **requis**. Le `ValidationPipe`
 * monté avec `whitelist: true` retire alors ce champ de toute requête qui
 * l'enverrait encore — mais **`whitelist` ne remplit pas une colonne**. Il ne
 * corrige que la FORME de la requête.
 *
 * `CommercantService.register` et `.createByAgent` construisent l'entité par
 * `create({ ...rest })` : plus rien n'y pose `communeId`. Face à une colonne
 * `NOT NULL`, chaque `POST /commercant/register` et chaque
 * `POST /agent/commercant` aurait donc levé un `23502 not_null_violation`,
 * soit un **500 sur toute création de commerçant** entre ce lot et le `DROP`
 * final. Et comme `provision-decor.sh` crée un commerçant, le décor des bancs
 * serait tombé avec — donc les lots suivants, qui en dépendent.
 *
 * Le défaut a été trouvé par une revue adverse du plan, pas par un contrôle :
 * rien n'aurait échoué avant l'exécution, et le premier symptôme aurait été un
 * décor cassé accusant autre chose.
 *
 * ── Pourquoi l'entité change dans le même commit (règle #12) ────────────────
 *
 * L'index et la contrainte de clé étrangère survivent tels quels ; seule la
 * nullabilité bouge. Mais si l'entité gardait `@Column()` non nullable pendant
 * que la base l'autorise, `migration:generate` cesserait de rendre RIEN — et
 * la sortie vide est la seule normale de ce dépôt depuis
 * `AlignConstraintNamesWithTypeorm`. Les deux moitiés vont ensemble.
 *
 * ── Ce que cette migration ne fait PAS ──────────────────────────────────────
 *
 * Aucun `UPDATE`, aucune perte : toutes les lignes existantes gardent leur
 * `communeId`. C'est même **indispensable** — c'est cette donnée que le lot L7
 * recopiera vers `adresse` avant de la détruire, et cette recopie n'a qu'une
 * seule fenêtre.
 *
 * ── Réversible, contrairement à celle de L7 ─────────────────────────────────
 *
 * ⚠️ Le `down()` ci-dessous ne l'est qu'à une condition : qu'aucune ligne
 * `communeId IS NULL` n'ait été créée entre-temps. Postgres refusera le
 * `SET NOT NULL` sinon, et c'est le bon comportement — il n'existe aucune
 * valeur juste à inventer pour un commerçant inscrit après ce chantier.
 */
export class MakeCommercantCommuneNullable1783860000000 implements MigrationInterface {
  name = 'MakeCommercantCommuneNullable1783860000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ALTER COLUMN "communeId" DROP NOT NULL`,
    );
    // ⚠️ **La contrainte de clé étrangère part MAINTENANT, pas en L7.** La
    // relation `@ManyToOne(() => Commune)` disparaît de l'entité dans ce même
    // lot ; la laisser en base ferait diverger entité et schéma, et
    // `migration:generate` cesserait de rendre RIEN — c'est d'ailleurs
    // exactement ce qu'il a signalé, et la seule divergence qu'il ait
    // signalée (mesuré le 2026-08-13).
    //
    // La **colonne** et sa donnée restent intactes : c'est elle que L7
    // recopiera vers `adresse`. Seule l'intégrité référentielle est levée, et
    // plus rien n'écrit dans cette colonne de toute façon.
    await queryRunner.query(
      `ALTER TABLE "commercant" DROP CONSTRAINT "FK_c017a3a877de774baf103f4c0b8"`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "commercant" ADD CONSTRAINT "FK_c017a3a877de774baf103f4c0b8" ` +
        `FOREIGN KEY ("communeId") REFERENCES "commune"("id") ` +
        `ON DELETE NO ACTION ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "commercant" ALTER COLUMN "communeId" SET NOT NULL`,
    );
  }
}

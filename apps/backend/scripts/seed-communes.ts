/**
 * Seed du référentiel Commune pour la wilaya de Djelfa (pilote V0).
 *
 * ATTENTION — liste à vérifier avant mise en production : reconstituée par
 * recherche web (aucun accès direct aux sources officielles type
 * interieur.gov.dz / ONS depuis cet environnement de développement au
 * moment de l'écriture de ce script). Idempotent (upsert par nom+wilaya) :
 * à corriger et relancer si des noms sont manquants ou mal orthographiés.
 *
 * Usage : npm run seed:communes
 */
import 'dotenv/config';
import { DataSource } from 'typeorm';
import { Commune } from '../src/commune/entities/commune.entity';

const WILAYA = 'Djelfa';

const COMMUNES_DJELFA = [
  'Djelfa',
  'Ain Oussara',
  'Amourah',
  'Benhar',
  'Beni Yagoub',
  'Birine',
  'Bouira Lahdab',
  'Charef',
  'Dar Chioukh',
  'Deldoul',
  'Douis',
  'El Guedid',
  'El Idrissia',
  'El Khemis',
  'Faidh El Botma',
  'Guernini',
  'Guettara',
  'Had-Sahary',
  'Hassi Bahbah',
  'Hassi El Euch',
  'Hassi Fedoul',
  'Messaad',
  "M'Liliha",
  'Moudjebara',
  'Oum Laadham',
  'Sed Rahal',
  'Selmana',
  'Sidi Baizid',
  'Sidi Ladjel',
  'Tadmit',
  'Zaafrane',
  'Zaccar',
  'Ain Chouhada',
  'Ain El Bell',
  'Ain Maabed',
];

async function main() {
  const dataSource = new DataSource({
    type: 'postgres',
    url: process.env.DATABASE_URL,
    entities: [Commune],
  });
  await dataSource.initialize();

  const repository = dataSource.getRepository(Commune);
  let created = 0;

  for (const nom of COMMUNES_DJELFA) {
    const existing = await repository.findOne({ where: { nom, wilaya: WILAYA } });
    if (!existing) {
      await repository.save(repository.create({ nom, wilaya: WILAYA }));
      created += 1;
    }
  }

  console.log(`${created} commune(s) créée(s) pour la wilaya de ${WILAYA}`);
  await dataSource.destroy();
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});

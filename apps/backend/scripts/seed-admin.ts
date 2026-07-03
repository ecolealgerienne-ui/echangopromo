/**
 * Bootstrap manuel du premier compte admin (specs §2 — pas d'auto-inscription
 * admin). Usage : npm run seed:admin -- admin@echango.com "mot-de-passe" "Nom"
 */
import 'dotenv/config';
import * as bcrypt from 'bcryptjs';
import { DataSource } from 'typeorm';
import { Admin } from '../src/admin/entities/admin.entity';

async function main() {
  const [email, password, nom] = process.argv.slice(2);
  if (!email || !password || !nom) {
    console.error('Usage: npm run seed:admin -- <email> <password> <nom>');
    process.exit(1);
  }

  const dataSource = new DataSource({
    type: 'postgres',
    url: process.env.DATABASE_URL,
    entities: [Admin],
  });
  await dataSource.initialize();

  const repository = dataSource.getRepository(Admin);
  const existing = await repository.findOne({ where: { email } });
  if (existing) {
    console.error(`Un admin existe déjà avec l'email ${email}`);
    await dataSource.destroy();
    process.exit(1);
  }

  const passwordHash = await bcrypt.hash(password, 10);
  await repository.save(repository.create({ email, passwordHash, nom }));

  console.log(`Admin créé : ${email}`);
  await dataSource.destroy();
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});

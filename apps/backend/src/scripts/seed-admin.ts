/**
 * Bootstrap manuel du premier compte admin, **et rotation de son mot de
 * passe** (specs §2 — pas d'auto-inscription admin).
 *
 * ── Pourquoi la rotation vit ICI ─────────────────────────────────────────
 *
 * Jusqu'au 2026-08-05, **le mot de passe admin ne pouvait pas être changé du
 * tout** : ce script refusait un compte existant, et aucune route ne le
 * permettait — `POST /admin/agent/:id/reset-password` ne vise que les agents.
 * L'action « faire tourner le mot de passe `superadmin` », ouverte au registre
 * depuis que l'APK de test s'est révélé porter les identifiants en clair,
 * était donc **irréalisable** sans SQL direct. Un point de sécurité qu'on ne
 * peut pas exécuter reste ouvert indéfiniment.
 *
 * ⚠️ **Et pas une route en libre-service**, délibérément. Un
 * `PATCH /admin/me/password` exigerait le mot de passe actuel — c'est-à-dire
 * celui qui a fuité. L'attaquant pourrait s'en servir pour verrouiller le
 * propriétaire dehors. Un script à exécuter avec l'accès base, lui, suppose un
 * accès que l'attaquant n'a pas.
 *
 * Usage : npm run seed:admin -- admin@echango.com "mot-de-passe" "Nom"
 * ou, sans argument, via les variables d'environnement ADMIN_EMAIL /
 * ADMIN_PASSWORD / ADMIN_NOM (pratique pour reseeder après un reset de la
 * base de dev sans retaper la commande) — les arguments CLI restent
 * prioritaires s'ils sont fournis.
 *
 * Sous src/ (pas un dossier scripts/ séparé à la racine du backend) pour
 * être compilé par `nest build` dans dist/scripts/ — l'image Docker de prod
 * ne contient que dist/ et les dependencies (pas ts-node ni les sources),
 * donc ce script doit pouvoir tourner en `node dist/scripts/seed-admin.js`
 * (voir script npm "seed:admin:prod").
 */
import 'dotenv/config';
import * as bcrypt from 'bcryptjs';
import { DataSource } from 'typeorm';
import { Admin } from '../admin/entities/admin.entity';

async function main() {
  const args = process.argv.slice(2);
  // ⚠️ Retiré des positionnels AVANT lecture : sans ça, `--rotate` glissé en
  // deuxième position deviendrait le mot de passe.
  const rotate = args.includes('--rotate');
  const [argEmail, argPassword, argNom] = args.filter((a) => a !== '--rotate');
  const email = argEmail || process.env.ADMIN_EMAIL;
  const password = argPassword || process.env.ADMIN_PASSWORD;
  const nom = argNom || process.env.ADMIN_NOM;
  if (!email || !password || !nom) {
    console.error(
      'Usage: npm run seed:admin -- <email> <password> <nom> [--rotate]\n' +
        '(ou définir ADMIN_EMAIL / ADMIN_PASSWORD / ADMIN_NOM dans .env)\n\n' +
        '  --rotate  remplace le mot de passe d’un admin EXISTANT et coupe\n' +
        '            ses sessions en cours.',
    );
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

  if (existing && !rotate) {
    console.error(
      `Un admin existe déjà avec l'email ${email}\n` +
        'Pour remplacer son mot de passe, relancer avec --rotate.',
    );
    await dataSource.destroy();
    process.exit(1);
  }

  const passwordHash = await bcrypt.hash(password, 10);

  if (existing) {
    // ⚠️ **La rotation coupe les sessions, et c'est le cœur du geste.**
    // Changer le mot de passe sans incrémenter `tokenVersion` ne protège de
    // rien : un jeton déjà volé reste valide jusqu'à expiration — 30 jours
    // ici (`JWT_EXPIRES_IN`). On aurait fermé la porte en laissant la fenêtre
    // ouverte (règle 6).
    existing.passwordHash = passwordHash;
    existing.nom = nom;
    existing.tokenVersion = (existing.tokenVersion ?? 0) + 1;
    await repository.save(existing);
    console.log(
      `Mot de passe remplacé : ${email}\n` +
        `Sessions coupées (tokenVersion → ${existing.tokenVersion}).`,
    );
    await dataSource.destroy();
    return;
  }

  await repository.save(repository.create({ email, passwordHash, nom }));

  console.log(`Admin créé : ${email}`);
  await dataSource.destroy();
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});

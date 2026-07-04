const INSECURE_JWT_SECRETS = new Set(['change-me', 'secret', 'changeme', '']);

/**
 * Passé à `ConfigModule.forRoot({ validate })` — échoue le démarrage plutôt
 * que de laisser tourner un backend avec un JWT_SECRET par défaut ou absent
 * (audit règle : un secret trivial rend tous les rôles usurpables).
 */
export function validateEnv(
  env: Record<string, unknown>,
): Record<string, unknown> {
  const jwtSecret = env.JWT_SECRET as string | undefined;
  if (!jwtSecret) {
    throw new Error('JWT_SECRET manquant — définir une valeur dans .env avant de démarrer.');
  }
  // La valeur par défaut ('change-me') reste tolérée en dev/pilote (le
  // .env.example la fournit pour démarrer sans friction) mais est rejetée
  // en production, où un secret trivial rendrait tous les rôles usurpables.
  if (env.NODE_ENV === 'production') {
    if (INSECURE_JWT_SECRETS.has(jwtSecret) || jwtSecret.length < 32) {
      throw new Error(
        'JWT_SECRET invalide pour la production : valeur par défaut ou trop ' +
          'courte (32 caractères minimum) — définir une valeur forte et unique.',
      );
    }
  }
  return env;
}

import { ClassSerializerInterceptor, ValidationPipe } from '@nestjs/common';
import { NestFactory, Reflector } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import compression from 'compression';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/errors/all-exceptions.filter';

function parseCorsOrigins(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  // Fait confiance au 1er hop (Traefik en prod) pour dériver la vraie IP
  // client depuis X-Forwarded-For — sans ça, `req.ip` (utilisé par
  // @nestjs/throttler pour le rate-limiting par IP, CLAUDE.md règles
  // #2/#7) vaut l'IP interne du reverse proxy pour TOUTES les requêtes,
  // faisant partager le même compteur de rate-limit à tous les clients
  // (audit sécurité 2026-07-06 : docs/AUDIT_SECURITE_PROD_2026-07.md).
  // `1` (pas `true`) : ne fait confiance qu'au proxy immédiat, pas à toute
  // la chaîne X-Forwarded-For (qu'un client pourrait sinon falsifier pour
  // usurper une IP et contourner la limite).
  app.set('trust proxy', 1);
  // Compresse les réponses JSON (listes promo/modération...) — notable sur
  // le réseau mobile variable du marché cible (même logique "coût data" que
  // la compression d'image côté upload, audit performance 2026-07-12).
  app.use(compression());
  // L'app mobile (Dio natif) n'est pas soumise au CORS — seul un futur
  // frontend web (admin) en aurait besoin. Pas d'origine par défaut tant
  // qu'aucun frontend web n'existe (CORS_ORIGINS vide = aucune origine
  // autorisée), plutôt que la config permissive par défaut de NestJS.
  const corsOrigins = parseCorsOrigins(process.env.CORS_ORIGINS);
  app.enableCors({
    origin: corsOrigins.length > 0 ? corsOrigins : false,
    credentials: true,
  });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  // Uniformise les réponses d'erreur en {statusCode, code, message} (codes
  // d'erreur i18n-ready, voir common/errors/).
  app.useGlobalFilters(new AllExceptionsFilter());
  // Applique les @Exclude() des entités (passwordHash, pinHash...) aux réponses JSON.
  app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
  await app.listen(process.env.PORT ?? 3000);
}
void bootstrap();

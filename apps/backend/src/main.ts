import { ClassSerializerInterceptor, ValidationPipe } from '@nestjs/common';
import { NestFactory, Reflector } from '@nestjs/core';
import { AppModule } from './app.module';

function parseCorsOrigins(raw: string | undefined): string[] {
  return (raw ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
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
  // Applique les @Exclude() des entités (passwordHash, pinHash...) aux réponses JSON.
  app.useGlobalInterceptors(new ClassSerializerInterceptor(app.get(Reflector)));
  await app.listen(process.env.PORT ?? 3000);
}
void bootstrap();

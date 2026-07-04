import 'dotenv/config';
import { DataSource, DataSourceOptions } from 'typeorm';

/**
 * Config partagée entre le bootstrap NestJS (app.module.ts) et la CLI
 * TypeORM (migrations) — une seule source de vérité pour `synchronize`
 * (toujours false : plus de dépendance à NODE_ENV, cause du finding audit
 * "chemin de déploiement Docker fragile ou dangereux selon la config .env").
 */
export const typeOrmBaseOptions = {
  type: 'postgres' as const,
  url: process.env.DATABASE_URL,
  synchronize: false,
};

export const dataSourceOptions: DataSourceOptions = {
  ...typeOrmBaseOptions,
  entities: [__dirname + '/**/*.entity{.ts,.js}'],
  migrations: [__dirname + '/migrations/*{.ts,.js}'],
};

export default new DataSource(dataSourceOptions);

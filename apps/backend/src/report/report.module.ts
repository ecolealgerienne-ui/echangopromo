import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Promo } from '../promo/entities/promo.entity';
import { PromoModule } from '../promo/promo.module';
import { ReportController } from './report.controller';
import { ReportService } from './report.service';
import { Report } from './entities/report.entity';

@Module({
  imports: [
    // ⚠️ **Accès direct à l'entité `Promo` EN PLUS de `PromoModule`** — les deux
    // ensemble, et c'est délibéré (règle #9).
    //
    // `PromoModule` est importé pour `PromoService`, dont `ReportService` a
    // besoin pour la définition partagée de « promo visible » : la répliquer
    // ici ferait diverger la règle, exactement le défaut que la règle #8 a
    // produit une fois déjà.
    //
    // Le `forFeature([Promo])` sert, lui, à la bascule de `moderationStatus`
    // au franchissement du seuil de signalements, écrite directement sur le
    // dépôt. La passer par `PromoService` demanderait d'y exposer une méthode
    // qui n'a de sens que pour la modération.
    //
    // ⚠️ Ce commentaire manquait, alors que `commercant.module.ts` renvoie ici
    // pour la justification (« même pattern que ReportModule pour la même
    // raison ») : le renvoi pointait vers du vide. Ajouté le 2026-08-05.
    TypeOrmModule.forFeature([Report, Promo]),
    PromoModule,
  ],
  controllers: [ReportController],
  providers: [ReportService],
  exports: [ReportService],
})
export class ReportModule {}

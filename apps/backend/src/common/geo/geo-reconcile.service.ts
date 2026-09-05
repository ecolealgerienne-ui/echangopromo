import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Not, IsNull, Repository } from 'typeorm';
import { configNumber } from '../config/config-number';
import {
  Commercant,
  CommercantGeocodageStatut,
} from '../../commercant/entities/commercant.entity';
import { GeoClientService, GeoUnavailableError } from './geo-client.service';

/**
 * Rattrape le géocodage inverse que `CommercantService.setPosition` n'a pas pu
 * faire au moment de la pose (echango-geo momentanément injoignable) et, une
 * fois après la migration, géocode le parc déjà positionné (`a_faire`).
 *
 * ── Pourquoi c'est BEAUCOUP plus simple que le cron qui vivait côté Odoo ───
 *
 * Le cron Odoo devait : cadencer à 1 req/s (politique de l'instance Nominatim
 * publique), découper en lots, distinguer le 429 d'un échec ordinaire,
 * détecter une dérive de position de plus de 200 m parce qu'il recevait la
 * position par synchro sans pouvoir s'accrocher à l'écriture.
 *
 * Ici, rien de tout ça :
 *  - `echango-geo` est local et auto-hébergé — pas de quota, pas de 429 ;
 *  - `setPosition` est **le seul écrivain** de `latitude`/`longitude` et
 *    re-géocode à chaque changement, donc `geocodage{Latitude,Longitude}`
 *    reste toujours égal à la position pour une fiche `fait` : **aucune dérive
 *    possible**, aucune passe de re-géocodage à prévoir ;
 *  - ce reconcile ne traite donc que deux cas : le rattrapage post-migration
 *    et la reprise d'un `setPosition` dont l'appel geo a échoué.
 */
@Injectable()
export class GeoReconcileService {
  private readonly logger = new Logger(GeoReconcileService.name);

  constructor(
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    private readonly geo: GeoClientService,
    private readonly config: ConfigService,
  ) {}

  private taille(): number {
    return configNumber(
      this.config.get('GEO_RECONCILE_BATCH'),
      200,
      'GEO_RECONCILE_BATCH',
      { minimum: 1, maximum: 5000 },
    );
  }

  @Cron(CronExpression.EVERY_30_MINUTES, { name: 'geo-reconcile' })
  async reconcilier(): Promise<number> {
    const aTraiter = await this.commercants.find({
      where: {
        geocodageStatut: In([
          CommercantGeocodageStatut.A_FAIRE,
          CommercantGeocodageStatut.ERREUR,
        ]),
        latitude: Not(IsNull()),
        longitude: Not(IsNull()),
      },
      // `a_faire` avant `erreur` : le travail neuf passe avant les échecs
      // persistants (même ordre que l'ancien cron Odoo).
      order: { geocodageStatut: 'ASC', updatedAt: 'ASC' },
      take: this.taille(),
    });

    if (aTraiter.length === 0) return 0;

    let traitees = 0;
    for (const commercant of aTraiter) {
      try {
        const { ville, wilaya } = await this.geo.reverse(
          commercant.latitude as number,
          commercant.longitude as number,
        );
        commercant.villeGeocodee = ville;
        commercant.wilayaGeocodee = wilaya;
        commercant.geocodageStatut = ville
          ? CommercantGeocodageStatut.FAIT
          : CommercantGeocodageStatut.SANS_RESULTAT;
        commercant.geocodageLatitude = commercant.latitude;
        commercant.geocodageLongitude = commercant.longitude;
        commercant.geocodageAt = new Date();
        await this.commercants.save(commercant);
        traitees += 1;
      } catch (error) {
        if (error instanceof GeoUnavailableError) {
          // echango-geo est retombé pendant le lot : on s'arrête, les fiches
          // non traitées gardent leur état et le prochain passage les reprend.
          this.logger.warn(
            `echango-geo injoignable, lot interrompu après ${traitees} fiche(s)`,
          );
          break;
        }
        // Échec propre à cette fiche (save impossible…) : on la marque et on
        // continue, elle sera reprise.
        this.logger.error(
          `géocodage de ${commercant.id} échoué : ${(error as Error).message}`,
        );
        commercant.geocodageStatut = CommercantGeocodageStatut.ERREUR;
        await this.commercants.save(commercant).catch(() => undefined);
      }
    }

    if (traitees > 0) {
      this.logger.log(`${traitees} fiche(s) géocodée(s)`);
    }
    return traitees;
  }
}

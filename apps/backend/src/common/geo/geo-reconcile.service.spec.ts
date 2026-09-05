import { ConfigService } from '@nestjs/config';
import { CommercantGeocodageStatut } from '../../commercant/entities/commercant.entity';
import type { Commercant } from '../../commercant/entities/commercant.entity';
import { GeoReconcileService } from './geo-reconcile.service';
import { GeoUnavailableError } from './geo-client.service';

/**
 * Le rattrapage du géocodage inverse, instancié à la main avec des doubles.
 *
 * Ce que ces cas verrouillent, et qui avait coûté 61 fiches côté Odoo :
 *  - `fait` quand une ville est trouvée, `sans_resultat` quand non — jamais
 *    `erreur` pour un point en mer ;
 *  - `erreur` n'est PAS terminal : ces fiches sont reprises au passage suivant
 *    (elles font partie de la requête) ;
 *  - si echango-geo retombe **pendant** le lot, on s'arrête — les fiches non
 *    traitées gardent leur état, pas de martèlement.
 */
describe('GeoReconcileService', () => {
  const config = { get: () => undefined } as unknown as ConfigService;

  function fiche(over: Partial<Commercant> = {}): Commercant {
    return {
      id: over.id ?? 'c1',
      latitude: 36.75,
      longitude: 3.05,
      geocodageStatut: CommercantGeocodageStatut.A_FAIRE,
      villeGeocodee: null,
      wilayaGeocodee: null,
      updatedAt: new Date(),
      ...over,
    } as Commercant;
  }

  function make(fiches: Commercant[], reverse: jest.Mock) {
    const saved: Commercant[] = [];
    const repo = {
      find: jest.fn().mockResolvedValue(fiches),
      save: jest.fn((c: Commercant) => {
        saved.push({ ...c });
        return Promise.resolve(c);
      }),
    };
    const geo = { reverse } as { reverse: jest.Mock };
    const service = new GeoReconcileService(repo as never, geo as never, config);
    return { service, repo, geo, saved };
  }

  it('ville trouvée → fait, coordonnées géocodées figées', async () => {
    const { service, saved } = make(
      [fiche()],
      jest.fn().mockResolvedValue({ ville: 'Oran', wilaya: 'Oran' }),
    );
    const n = await service.reconcilier();
    expect(n).toBe(1);
    expect(saved[0]).toMatchObject({
      villeGeocodee: 'Oran',
      wilayaGeocodee: 'Oran',
      geocodageStatut: CommercantGeocodageStatut.FAIT,
      geocodageLatitude: 36.75,
      geocodageLongitude: 3.05,
    });
  });

  it('pas de ville → sans_resultat (jamais erreur)', async () => {
    const { service, saved } = make(
      [fiche()],
      jest.fn().mockResolvedValue({ ville: null, wilaya: null }),
    );
    await service.reconcilier();
    expect(saved[0].geocodageStatut).toBe(
      CommercantGeocodageStatut.SANS_RESULTAT,
    );
  });

  it('echango-geo retombe pendant le lot → arrêt, fiches suivantes intactes', async () => {
    const reverse = jest
      .fn()
      .mockResolvedValueOnce({ ville: 'Alger', wilaya: 'Alger' })
      .mockRejectedValueOnce(new GeoUnavailableError('ECONNREFUSED'));
    const { service, repo } = make(
      [fiche({ id: 'a' }), fiche({ id: 'b' }), fiche({ id: 'c' })],
      reverse,
    );
    const n = await service.reconcilier();
    expect(n).toBe(1); // seule 'a' traitée
    expect(repo.save).toHaveBeenCalledTimes(1);
    expect(reverse).toHaveBeenCalledTimes(2); // 'a' ok, 'b' lève → break
  });

  it('rien à traiter → 0, aucun appel', async () => {
    const reverse = jest.fn();
    const { service } = make([], reverse);
    expect(await service.reconcilier()).toBe(0);
    expect(reverse).not.toHaveBeenCalled();
  });
});

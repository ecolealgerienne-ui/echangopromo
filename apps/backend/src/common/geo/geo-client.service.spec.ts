import { ConfigService } from '@nestjs/config';
import {
  GeoClientService,
  GeoUnavailableError,
} from './geo-client.service';

/**
 * Le client d'echango-geo, instancié à la main avec un `ConfigService` double
 * et `fetch` mocké (le dépôt n'a pas de client HTTP — `crm-push` fait pareil).
 *
 * Ce que ces cas verrouillent :
 *  - le mapping `city`→`ville`, `province`→`wilaya` (les noms qu'`echango-geo`
 *    rend, `docs/specs_echango_geo_v1.md`) ;
 *  - un point inconnu (`city` absent) rend `{ ville: null, wilaya: null }` —
 *    **pas** une exception (règle #10) ;
 *  - echango-geo injoignable, en 5xx ou en timeout → `GeoUnavailableError`,
 *    que l'appelant traduit en `geocodageStatut = a_faire` sans casser
 *    `setPosition`.
 */
describe('GeoClientService', () => {
  const config = {
    get: (k: string) =>
      ({
        GEO_SERVICE_URL: 'http://geo-api:3000',
        GEO_INTERNAL_TOKEN: 'jeton-test',
      })[k],
  } as unknown as ConfigService;

  let fetchMock: jest.Mock;
  let service: GeoClientService;

  const reponse = (status: number, body: unknown) => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });

  beforeEach(() => {
    fetchMock = jest.fn();
    global.fetch = fetchMock as unknown as typeof fetch;
    service = new GeoClientService(config);
  });

  it('mappe city→ville et province→wilaya, et porte le jeton', async () => {
    fetchMock.mockResolvedValue(
      reponse(200, { city: 'Alger', province: 'Alger', country: 'DZ' }),
    );
    await expect(service.reverse(36.75, 3.05)).resolves.toEqual({
      ville: 'Alger',
      wilaya: 'Alger',
    });
    const [url, opts] = fetchMock.mock.calls[0];
    expect(url).toContain('/v1/geocode/reverse?lat=36.75&lon=3.05');
    expect(opts.headers['X-Internal-Token']).toBe('jeton-test');
  });

  it('point inconnu (city absent) → { ville: null, wilaya: null }, pas d’erreur', async () => {
    fetchMock.mockResolvedValue(reponse(200, { label: '' }));
    await expect(service.reverse(30, -40)).resolves.toEqual({
      ville: null,
      wilaya: null,
    });
  });

  it('chaîne vide traitée comme null', async () => {
    fetchMock.mockResolvedValue(reponse(200, { city: '   ', province: '' }));
    await expect(service.reverse(1, 1)).resolves.toEqual({
      ville: null,
      wilaya: null,
    });
  });

  it('echango-geo en 503 → GeoUnavailableError', async () => {
    fetchMock.mockResolvedValue(reponse(503, {}));
    await expect(service.reverse(36.75, 3.05)).rejects.toBeInstanceOf(
      GeoUnavailableError,
    );
  });

  it('echango-geo injoignable → GeoUnavailableError', async () => {
    fetchMock.mockRejectedValue(
      Object.assign(new Error('fetch failed'), { code: 'ECONNREFUSED' }),
    );
    await expect(service.reverse(36.75, 3.05)).rejects.toBeInstanceOf(
      GeoUnavailableError,
    );
  });

  it('timeout (AbortError) → GeoUnavailableError', async () => {
    fetchMock.mockRejectedValue(
      Object.assign(new Error('aborted'), { name: 'AbortError' }),
    );
    await expect(service.reverse(1, 1)).rejects.toBeInstanceOf(
      GeoUnavailableError,
    );
  });

  it('ping : /health répond → reachable:true', async () => {
    fetchMock.mockResolvedValue(reponse(200, {}));
    await expect(service.ping()).resolves.toEqual({ reachable: true });
  });

  it('ping : échec → reachable:false sans lever', async () => {
    fetchMock.mockRejectedValue(new Error('down'));
    await expect(service.ping()).resolves.toEqual({ reachable: false });
  });
});

import { _resetConfigNumberLog } from '../common/config/config-number';
import { PromoService } from './promo.service';

/**
 * **Ce que ce banc prouve : que l'intervalle signé est BRANCHÉ, pas seulement
 * disponible.**
 *
 * `config-number.spec.ts` établit que `configNumber` sait accepter une valeur
 * négative *quand on le lui demande*. Ça ne dit rien de l'appelant — et c'est
 * exactement le trou de la règle #31 : une capacité correcte, appelée avec les
 * mauvaises options, ne produit aucune erreur. Elle produit une longitude ouest
 * qui retombe silencieusement sur Alger.
 *
 * D'où le cas central ci-dessous : `CLIENT_DEFAULT_LONGITUDE=-0.64` (Oran) doit
 * **ressortir à −0.64**. S'il ressort à 3.0588, c'est que `{ minimum: -180 }`
 * manque dans `getClientConfig` — et rien d'autre dans le dépôt ne le dirait.
 *
 * ⚠️ Autant de cas qui doivent refuser que de cas qui passent (règle #28).
 */
describe('PromoService.getClientConfig', () => {
  /**
   * Le service est instancié à la main avec des doubles (même approche que
   * `highlight.service.spec.ts`) : `getClientConfig` ne touche ni la base ni le
   * stockage, seul `configService` compte.
   */
  function serviceAvec(env: Record<string, string>): PromoService {
    const configService = { get: (cle: string) => env[cle] };
    return new PromoService(
      undefined as never,
      undefined as never,
      undefined as never,
      undefined as never,
      configService as never,
      undefined as never,
    );
  }

  beforeEach(() => _resetConfigNumberLog());

  // ── Doivent PASSER ────────────────────────────────────────────────────────

  it('sert une longitude OUEST — le cas que tout ce chantier vise', () => {
    // Oran. Sans `{ minimum: -180 }` dans getClientConfig, `configNumber`
    // refuse le négatif et rend le repli : le backend démarrerait, servirait
    // Alger, et laisserait une ligne de journal que personne ne relit.
    const config = serviceAvec({ CLIENT_DEFAULT_LONGITUDE: '-0.64' });
    expect(config.getClientConfig().defaultLongitude).toBe(-0.64);
  });

  it('sert une latitude sud et le méridien zéro', () => {
    expect(
      serviceAvec({ CLIENT_DEFAULT_LATITUDE: '-33.9' }).getClientConfig()
        .defaultLatitude,
    ).toBe(-33.9);
    expect(
      serviceAvec({ CLIENT_DEFAULT_LONGITUDE: '0' }).getClientConfig()
        .defaultLongitude,
    ).toBe(0);
  });

  it('conserve les décimales — une coordonnée tronquée déplace la carte', () => {
    const config = serviceAvec({
      CLIENT_DEFAULT_LATITUDE: '36.7538',
      CLIENT_DEFAULT_LONGITUDE: '3.0588',
    }).getClientConfig();
    expect(config.defaultLatitude).toBe(36.7538);
    expect(config.defaultLongitude).toBe(3.0588);
  });

  it('retombe sur Alger quand rien n’est configuré', () => {
    const config = serviceAvec({}).getClientConfig();
    expect(config.defaultLatitude).toBe(36.7538);
    expect(config.defaultLongitude).toBe(3.0588);
    expect(config.defaultRadiusKm).toBe(5);
    expect(config.maxRadiusKm).toBe(50);
  });

  /**
   * ⚠️ **Le défaut fondateur, transposé.** `configService.get<number>` ne
   * convertit rien : la valeur arrive en chaîne. Tant que l'usage est
   * arithmétique, JavaScript coerce et personne ne voit rien — le masque tombe
   * quand la valeur **sort en JSON**, et c'est précisément ce que fait cette
   * route. `GET /promo/me/slots` a failli servir `{"plafond":"5"}` à un mobile
   * qui fait `as int` (revue 2026-08-05). Ici ce serait `as double`.
   */
  it('rend des nombres, jamais des chaînes — la route les sérialise en JSON', () => {
    const config = serviceAvec({
      CLIENT_DEFAULT_LATITUDE: '36.7538',
      CLIENT_DEFAULT_LONGITUDE: '-0.64',
      CLIENT_DEFAULT_RADIUS_KM: '5',
      CLIENT_MAX_RADIUS_KM: '50',
    }).getClientConfig();
    for (const valeur of Object.values(config)) {
      expect(typeof valeur).toBe('number');
    }
  });

  // ── Doivent REFUSER (et retomber sur le repli) ────────────────────────────

  it('refuse une coordonnée hors du globe', () => {
    expect(
      serviceAvec({ CLIENT_DEFAULT_LONGITUDE: '200' }).getClientConfig()
        .defaultLongitude,
    ).toBe(3.0588);
    expect(
      serviceAvec({ CLIENT_DEFAULT_LONGITUDE: '-200' }).getClientConfig()
        .defaultLongitude,
    ).toBe(3.0588);
    expect(
      serviceAvec({ CLIENT_DEFAULT_LATITUDE: '-91' }).getClientConfig()
        .defaultLatitude,
    ).toBe(36.7538);
    expect(
      serviceAvec({ CLIENT_DEFAULT_LATITUDE: '91' }).getClientConfig()
        .defaultLatitude,
    ).toBe(36.7538);
  });

  it('refuse une coordonnée illisible', () => {
    const config = serviceAvec({
      CLIENT_DEFAULT_LATITUDE: 'abc',
      CLIENT_DEFAULT_LONGITUDE: '',
    }).getClientConfig();
    expect(config.defaultLatitude).toBe(36.7538);
    expect(config.defaultLongitude).toBe(3.0588);
  });

  /**
   * ⚠️ Les rayons ne sont **pas** des intervalles signés : un rayon nul ou
   * négatif n'a aucun sens, et le garde-fou historique doit rester actif sur
   * eux. C'est ce cas qui interdit de « lever le refus partout » en croyant
   * simplifier.
   */
  it('refuse un rayon nul ou négatif — le garde-fou tient sur les rayons', () => {
    expect(
      serviceAvec({ CLIENT_DEFAULT_RADIUS_KM: '0' }).getClientConfig()
        .defaultRadiusKm,
    ).toBe(5);
    expect(
      serviceAvec({ CLIENT_DEFAULT_RADIUS_KM: '-5' }).getClientConfig()
        .defaultRadiusKm,
    ).toBe(5);
    expect(
      serviceAvec({ CLIENT_MAX_RADIUS_KM: '-1' }).getClientConfig().maxRadiusKm,
    ).toBe(50);
  });
});

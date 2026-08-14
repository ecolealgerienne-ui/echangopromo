import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { ListPromoQueryDto } from './list-promo-query.dto';

/**
 * **Ce que ce banc prouve : que le point de recherche sait être REFUSÉ.**
 *
 * Le cas fondateur est `?latitude=` (présent, vide). `Number('')` vaut `0`, et
 * `@IsLatitude()` **accepte** zéro — c'est l'équateur, une coordonnée
 * parfaitement légitime. Sans le transform du DTO, une requête cassée
 * n'enverrait donc aucune erreur : elle chercherait des promos au large du
 * Gabon. C'est le miroir exact du piège des prix (`create-promo.dto.spec.ts`),
 * et il est plus vicieux, parce que la valeur produite est valide.
 *
 * Le second est la paire dépareillée : une latitude sans longitude est une
 * requête cassée, **pas** une requête sans position. La traiter comme une
 * absence appliquerait silencieusement le point par défaut du serveur et
 * rendrait des résultats plausibles, faux, et indiscernables des vrais
 * (règle #29).
 *
 * ⚠️ Autant de cas qui doivent ÉCHOUER que de cas qui passent (règle #28).
 */
describe('ListPromoQueryDto — le périmètre géographique', () => {
  const erreursDe = (patch: Record<string, unknown>): string[] => {
    const dto = plainToInstance(ListPromoQueryDto, patch);
    return validateSync(dto)
      .map((e) => e.property)
      .sort();
  };

  // ── Doivent PASSER ────────────────────────────────────────────────────────

  it('accepte une requête sans aucune position — le serveur appliquera son défaut', () => {
    expect(erreursDe({})).toEqual([]);
  });

  it('accepte un point transmis en chaîne, comme le fait une query string', () => {
    // Le cas réel : tout paramètre d'URL arrive en texte. C'est exactement ce
    // que `configService.get<number>` laissait passer côté configuration.
    expect(erreursDe({ latitude: '34.6703', longitude: '3.2630' })).toEqual([]);
  });

  it('accepte une longitude ouest et le méridien zéro', () => {
    expect(erreursDe({ latitude: '35.69', longitude: '-0.64' })).toEqual([]);
    expect(erreursDe({ latitude: '0', longitude: '0' })).toEqual([]);
  });

  it('accepte les bornes exactes du globe', () => {
    expect(erreursDe({ latitude: '90', longitude: '180' })).toEqual([]);
    expect(erreursDe({ latitude: '-90', longitude: '-180' })).toEqual([]);
  });

  it('accepte un rayon, y compris décimal', () => {
    expect(
      erreursDe({ latitude: '34.6', longitude: '3.2', radiusKm: '5' }),
    ).toEqual([]);
    expect(
      erreursDe({ latitude: '34.6', longitude: '3.2', radiusKm: '2.5' }),
    ).toEqual([]);
  });

  it('convertit réellement en nombre — la valeur ressort typée', () => {
    // Sans ça, `radiusKm > maxRadiusKm` comparerait une chaîne, et la borne
    // du service serait franchie sans un mot ('10' > 50 est faux).
    const dto = plainToInstance(ListPromoQueryDto, {
      latitude: '34.6703',
      longitude: '3.2630',
      radiusKm: '5',
    });
    expect(typeof dto.latitude).toBe('number');
    expect(typeof dto.longitude).toBe('number');
    expect(typeof dto.radiusKm).toBe('number');
    expect(dto.latitude).toBe(34.6703);
  });

  // ── Doivent REFUSER ───────────────────────────────────────────────────────

  /**
   * ⚠️ **Le cas qui justifie tout le transform.** `@Type(() => Number)` suffit
   * pour `page`/`limit`, parce que `@Min(1)` rattrape le zéro. Il ne suffit
   * **pas** ici : zéro est une latitude valide.
   */
  it('refuse un paramètre présent mais vide — sinon c’est l’équateur en silence', () => {
    expect(erreursDe({ latitude: '', longitude: '' })).toEqual([
      'latitude',
      'longitude',
    ]);
    expect(erreursDe({ latitude: '   ', longitude: '   ' })).toEqual([
      'latitude',
      'longitude',
    ]);
  });

  it('refuse une latitude sans longitude, et l’inverse', () => {
    expect(erreursDe({ latitude: '34.6703' })).toEqual(['longitude']);
    expect(erreursDe({ longitude: '3.2630' })).toEqual(['latitude']);
  });

  it('refuse une coordonnée hors du globe', () => {
    expect(erreursDe({ latitude: '91', longitude: '3.2' })).toEqual([
      'latitude',
    ]);
    expect(erreursDe({ latitude: '34.6', longitude: '181' })).toEqual([
      'longitude',
    ]);
    expect(erreursDe({ latitude: '-91', longitude: '-181' })).toEqual([
      'latitude',
      'longitude',
    ]);
  });

  it('refuse une coordonnée illisible', () => {
    expect(erreursDe({ latitude: 'abc', longitude: 'def' })).toEqual([
      'latitude',
      'longitude',
    ]);
  });

  /**
   * ⚠️ Règle #34 : établir que c'est un nombre **fini**, jamais le supposer.
   * Le précédent est `dureeJours`, où `NaN <= x` et `NaN > y` étaient tous
   * deux faux — la valeur traversait les deux gardes.
   */
  it('refuse un rayon nul, négatif, infini ou illisible', () => {
    const point = { latitude: '34.6', longitude: '3.2' };
    expect(erreursDe({ ...point, radiusKm: '0' })).toEqual(['radiusKm']);
    expect(erreursDe({ ...point, radiusKm: '-5' })).toEqual(['radiusKm']);
    expect(erreursDe({ ...point, radiusKm: 'Infinity' })).toEqual(['radiusKm']);
    expect(erreursDe({ ...point, radiusKm: 'abc' })).toEqual(['radiusKm']);
    expect(erreursDe({ ...point, radiusKm: '' })).toEqual(['radiusKm']);
  });

  /**
   * Le plafond métier n'est **pas** ici : il vaut `CLIENT_MAX_RADIUS_KM`, une
   * valeur de configuration, et le recopier dans ce DTO en ferait une seconde
   * source qui divergerait au premier changement de `.env` (règle #32). Ce
   * banc épingle donc l'absence de `@Max` comme un choix, pour que personne ne
   * la « corrige » en croyant combler un oubli — le refus existe, il est
   * prononcé par `PromoService.findActiveForClient`.
   */
  it('laisse passer un rayon démesuré — la borne métier est ailleurs, volontairement', () => {
    expect(
      erreursDe({ latitude: '34.6', longitude: '3.2', radiusKm: '100000' }),
    ).toEqual([]);
  });
});

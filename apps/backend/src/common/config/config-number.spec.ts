import { configNumber } from './config-number';

/**
 * **Ce que ce banc prouve : que la lecture de configuration sait REFUSER.**
 *
 * Le cas fondateur est le premier « doit refuser » : `configService.get` rend
 * une **chaîne**, et c'est précisément ce que l'annotation `<number>` laissait
 * croire converti. Le reste borde les conversions que JavaScript accepte trop
 * volontiers (`Number('')` vaut 0, `Number(' ')` aussi, `Number('5abc')` vaut
 * NaN mais `parseInt('5abc')` vaut 5).
 *
 * ⚠️ Autant de cas qui doivent refuser que de cas qui passent (règle #28).
 */
describe('configNumber — lecture d’un nombre de configuration', () => {
  // ── Doivent PASSER ────────────────────────────────────────────────────────

  it('convertit la chaîne rendue par ConfigService', () => {
    // Le cas réel : `.env` porte `PROMO_MAX_DURATION_DAYS=7`, donc le service
    // reçoit `'7'`. C'est un `number` qui doit en sortir, pas une chaîne.
    const v = configNumber('7', 5);
    expect(v).toBe(7);
    expect(typeof v).toBe('number');
  });

  it('laisse passer un nombre déjà typé', () => {
    expect(configNumber(7, 5)).toBe(7);
  });

  it('accepte un décimal', () => {
    expect(configNumber('1.5', 5)).toBe(1.5);
  });

  it('retombe sur le défaut quand la clé est absente', () => {
    expect(configNumber(undefined, 5)).toBe(5);
    expect(configNumber(null, 5)).toBe(5);
  });

  // ── Doivent REFUSER (et retomber sur le défaut) ───────────────────────────

  it('refuse une valeur non numérique', () => {
    expect(configNumber('abc', 5)).toBe(5);
    expect(configNumber('5abc', 5)).toBe(5);
  });

  it('refuse une chaîne vide ou blanche — Number() les rendrait 0', () => {
    expect(configNumber('', 5)).toBe(5);
    expect(configNumber('   ', 5)).toBe(5);
  });

  it('refuse zéro et le négatif — aucun plafond nul n’a de sens ici', () => {
    expect(configNumber('0', 5)).toBe(5);
    expect(configNumber('-3', 5)).toBe(5);
  });

  it('refuse l’infini et NaN', () => {
    expect(configNumber('Infinity', 5)).toBe(5);
    expect(configNumber(Infinity, 5)).toBe(5);
    expect(configNumber(NaN, 5)).toBe(5);
  });

  it('refuse un objet ou un tableau', () => {
    expect(configNumber({}, 5)).toBe(5);
    expect(configNumber([1, 2], 5)).toBe(5);
  });

  it('refuse un booléen — Number(true) vaudrait 1', () => {
    expect(configNumber(true, 5)).toBe(5);
  });
});

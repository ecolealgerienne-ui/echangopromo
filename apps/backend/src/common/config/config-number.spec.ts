import { Logger } from '@nestjs/common';
import { _resetConfigNumberLog, configNumber } from './config-number';

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

/**
 * **Le journal fait partie du contrat, pas de l'agrément.**
 *
 * Le repli de `configNumber` va contre la règle #29, et sa seule contrepartie
 * est de laisser une trace : sans elle, une clé absente est indiscernable
 * d'une clé présente valant exactement le défaut — c'est le diagnostic qui
 * manquera le jour où le réglage « ne marche pas » (règle #36, cas réel de
 * `PROMO_ACTIVE_CAP`). Un journal non éprouvé n'est donc pas un détail de
 * confort : c'est la moitié du mécanisme.
 */
describe('configNumber — le plancher', () => {
  beforeEach(() => _resetConfigNumberLog());

  it('accepte une valeur égale au minimum', () => {
    expect(configNumber('2', 3, 'SEUIL', { minimum: 2 })).toBe(2);
  });

  it('accepte une valeur au-dessus du minimum', () => {
    expect(configNumber('7', 3, 'SEUIL', { minimum: 2 })).toBe(7);
  });

  // ⚠️ Le cas qui justifie tout le reste : un seuil de modération à 1 laisse
  // UN signalement masquer la promo d'un concurrent (2026-07-12). Sans
  // plancher, ce réglage redeviendrait possible depuis un fichier.
  it('refuse une valeur sous le minimum et retombe sur le défaut', () => {
    expect(configNumber('1', 3, 'SEUIL', { minimum: 2 })).toBe(3);
  });

  it('refuse un décimal sous le minimum', () => {
    expect(configNumber('1.9', 3, 'SEUIL', { minimum: 2 })).toBe(3);
  });

  it('sans minimum, le comportement ne change pas', () => {
    expect(configNumber('1', 3, 'SEUIL')).toBe(1);
  });
});

describe('configNumber — la trace laissée par le repli', () => {
  let warn: jest.SpyInstance;
  // Les messages sont collectés ici plutôt que relus dans `warn.mock.calls` :
  // ce dernier est typé `any`, et les assertions dessus ne vaudraient rien.
  let messages: string[];

  beforeEach(() => {
    _resetConfigNumberLog();
    messages = [];
    warn = jest
      .spyOn(Logger.prototype, 'warn')
      .mockImplementation((message: unknown) => {
        messages.push(typeof message === 'string' ? message : '');
      });
  });

  afterEach(() => warn.mockRestore());

  it('signale une clé ABSENTE — sinon elle ressemble au défaut', () => {
    expect(configNumber(undefined, 5, 'PROMO_ACTIVE_CAP')).toBe(5);
    expect(messages).toHaveLength(1);
    expect(messages[0]).toContain('PROMO_ACTIVE_CAP');
    expect(messages[0]).toContain('absente');
  });

  it('signale une valeur illisible en la montrant telle quelle', () => {
    configNumber('abc', 5, 'PROMO_ACTIVE_CAP');
    expect(messages[0]).toContain('abc');
  });

  it('montre NaN et Infinity — JSON.stringify les rendrait tous deux "null"', () => {
    configNumber(NaN, 5, 'A');
    configNumber(Infinity, 5, 'B');
    expect(messages[0]).toContain('NaN');
    expect(messages[1]).toContain('Infinity');
  });

  it('ne dit rien quand la valeur est lisible', () => {
    expect(configNumber('7', 5, 'PROMO_MAX_DURATION_DAYS')).toBe(7);
    expect(messages).toHaveLength(0);
  });

  // ⚠️ Ces fonctions sont appelées PAR REQUÊTE. Un avertissement répété à
  // chaque publication de promo serait filtré par qui lit les journaux — donc
  // un repli redevenu silencieux par un autre chemin.
  it('ne répète pas le même avertissement à chaque appel', () => {
    for (let i = 0; i < 50; i++) configNumber(undefined, 5, 'PROMO_ACTIVE_CAP');
    expect(messages).toHaveLength(1);
  });

  it('mais ne confond pas deux clés différentes', () => {
    configNumber(undefined, 5, 'PROMO_ACTIVE_CAP');
    configNumber(undefined, 7, 'PROMO_MAX_DURATION_DAYS');
    expect(messages).toHaveLength(2);
  });
});

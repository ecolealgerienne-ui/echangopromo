import { TimeoutDepasseError, withTimeout } from './with-timeout';

/**
 * **Ce que ce banc prouve : que la borne sait REFUSER d'attendre.**
 *
 * Un helper de délai qui laisse toujours passer est un helper qu'on croit
 * posé. Le cas fondateur est le troisième : une promesse qui ne se résout
 * jamais doit rejeter au bout du délai — c'est exactement la forme qu'avait la
 * génération de miniature contre un `S3_ENDPOINT` injoignable (P9, 300 s).
 *
 * ⚠️ Autant de cas qui doivent refuser que de cas qui passent (règle #28).
 */
describe('withTimeout', () => {
  const jamais = <T>() => new Promise<T>(() => undefined);

  // ── Doivent PASSER ────────────────────────────────────────────────────────

  it('rend la valeur quand la promesse répond à temps', async () => {
    await expect(withTimeout(Promise.resolve('ok'), 50, 'test')).resolves.toBe(
      'ok',
    );
  });

  it('laisse passer une erreur métier telle quelle, sans la déguiser en délai', async () => {
    const echec = Promise.reject(new Error('refus métier'));
    await expect(withTimeout(echec, 50, 'test')).rejects.toThrow(
      'refus métier',
    );
  });

  it('n’attend pas le délai quand la réponse arrive avant', async () => {
    const debut = Date.now();
    await withTimeout(Promise.resolve(1), 5_000, 'test');
    // Si le minuteur n'était pas nettoyé, ce test durerait 5 s.
    expect(Date.now() - debut).toBeLessThan(1_000);
  });

  // ── Doivent REFUSER ───────────────────────────────────────────────────────

  it('rejette quand la promesse ne répond jamais — LE cas de P9', async () => {
    await expect(
      withTimeout(jamais<string>(), 20, 'miniature'),
    ).rejects.toThrow(TimeoutDepasseError);
  });

  it('nomme ce qui a dépassé, pas seulement le fait qu’il a dépassé', async () => {
    await expect(
      withTimeout(jamais<string>(), 20, 'miniature'),
    ).rejects.toThrow(/miniature.*20 ms/);
  });

  it('rejette aussi une promesse simplement TROP LENTE, pas seulement bloquée', async () => {
    const lente = new Promise((r) => setTimeout(() => r('trop tard'), 200));
    await expect(withTimeout(lente, 20, 'lente')).rejects.toThrow(
      TimeoutDepasseError,
    );
  });

  // ⚠️ **Ce test ne protège aucune ligne de `withTimeout`, et il faut le dire.**
  // Une première version posait un `promesse.catch(() => undefined)` défensif ;
  // la mutation l'a démenti — le retirer ne fait échouer personne, parce que
  // `Promise.race` s'abonne déjà à chaque promesse et qu'un rejet tardif y est
  // donc **géré** au sens de Node.
  //
  // Le test reste, non comme preuve d'une garde, mais comme garde-fou sur la
  // PROPRIÉTÉ : si un jour la course est remplacée par une construction qui
  // n'écoute plus le perdant, celui-ci deviendra un `unhandledRejection`
  // capable d'abattre le processus longtemps après la réponse. Il est nommé
  // pour ce qu'il est — sinon il compterait à tort comme un cas de refus.
  it('le rejet TARDIF du perdant ne devient pas un unhandledRejection', async () => {
    const rejets: unknown[] = [];
    const capter = (raison: unknown) => rejets.push(raison);
    process.on('unhandledRejection', capter);

    const tardive = new Promise((_, rej) =>
      setTimeout(() => rej(new Error('arrivé après la course')), 30),
    );
    await expect(withTimeout(tardive, 10, 'tardive')).rejects.toThrow(
      TimeoutDepasseError,
    );
    await new Promise((r) => setTimeout(r, 80));

    process.off('unhandledRejection', capter);
    expect(rejets).toEqual([]);
  });
});

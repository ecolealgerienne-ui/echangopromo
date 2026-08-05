/**
 * Borne l'attente d'une promesse **best-effort**.
 *
 * ── Pourquoi ce helper existe ────────────────────────────────────────────
 *
 * « Best-effort » ne veut rien dire tant que l'effort n'est pas borné. La
 * génération de miniature est facultative — une promo se crée très bien sans
 * elle — mais elle vit **dans le chemin de création**, donc son attente est
 * celle de l'utilisateur. Le 2026-08-04, un `S3_ENDPOINT` injoignable depuis
 * le serveur a fait durer une création de promo **plus de 300 secondes** :
 * le SDK AWS n'impose pas de délai court, et `try/catch` attrape l'échec sans
 * jamais borner l'attente (P9).
 *
 * Séparer les deux rôles de `S3_ENDPOINT` a réglé ce cas-là. Ce helper règle
 * la classe : n'importe quelle lenteur du stockage — réseau saturé, MinIO à
 * genoux, bucket distant — redevient un délai connu au lieu d'un blocage.
 *
 * ⚠️ **Ceci n'annule pas le travail sous-jacent.** La promesse d'origine
 * continue de tourner ; on cesse seulement de l'attendre. C'est acceptable
 * pour un effet accessoire (au pire une miniature écrite après coup et non
 * référencée, que la purge de rétention balaiera), et ça ne le serait pas pour
 * une écriture métier. Ne pas s'en servir pour borner une transaction.
 *
 * ⚠️ **Le rejet tardif du perdant ne produit PAS d'`unhandledRejection`**, et
 * ce n'est pas ce module qui l'évite : `Promise.race` s'abonne à chacune des
 * promesses qu'on lui passe, si bien qu'un rejet arrivé après la course est
 * remis à cette souscription — ignoré, mais **géré** au sens de Node.
 *
 * Une première version posait un `promesse.catch(() => undefined)` défensif,
 * avec un commentaire affirmant qu'il évitait d'abattre le processus. La
 * mutation l'a démenti : retirer la ligne ne fait échouer aucun test, parce
 * qu'elle ne servait à rien. Retirée plutôt que gardée « au cas où » — une
 * protection dont on ne peut pas montrer l'effet est une protection qu'on
 * croit avoir (règle #28).
 */
export class TimeoutDepasseError extends Error {
  constructor(
    readonly libelle: string,
    readonly delaiMs: number,
  ) {
    super(`${libelle} : délai de ${delaiMs} ms dépassé`);
    this.name = 'TimeoutDepasseError';
  }
}

export function withTimeout<T>(
  promesse: Promise<T>,
  delaiMs: number,
  libelle: string,
): Promise<T> {
  let minuteur: NodeJS.Timeout | undefined;
  const echeance = new Promise<never>((_, rejeter) => {
    minuteur = setTimeout(
      () => rejeter(new TimeoutDepasseError(libelle, delaiMs)),
      delaiMs,
    );
    // `unref` : ce minuteur ne doit pas retenir la boucle d'événements à
    // l'arrêt du processus. Sans ça, un délai long retarderait chaque sortie.
    minuteur.unref?.();
  });

  return Promise.race([promesse, echeance]).finally(() => {
    if (minuteur) clearTimeout(minuteur);
  });
}

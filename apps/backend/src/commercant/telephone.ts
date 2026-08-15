import { CountryCode, parsePhoneNumberFromString } from 'libphonenumber-js';

/**
 * **Le seul endroit qui sait à quoi ressemble un numéro de téléphone ici.**
 *
 * ⚠️ **Le défaut que ce module ferme existait avant le CRM, et il était déjà
 * grave.** Les DTO portaient `@IsPhoneNumber('DZ')`, qui accepte
 * indifféremment `0555000101` **et** `+213555000101` ; rien ne normalisait
 * avant l'écriture, et l'app affiche `+213...` en exemple de saisie. Les deux
 * formes du même numéro sont deux chaînes différentes : l'index unique ne les
 * rapproche pas, `findVivantByTelephone` ne trouve que la forme exacte saisie,
 * et **le même commerçant pouvait donc avoir deux comptes actifs** — ou ne pas
 * réussir à se connecter avec la forme qu'il n'avait pas utilisée à
 * l'inscription.
 *
 * ⚠️ **La forme stockée est l'E.164** — `+213555000101` — décision produit du
 * 2026-08-15. La saisie reste nationale (`0555000101`, le zéro de tête est
 * retiré à la conversion) : c'est ce que le commerçant lit sur sa devanture, et
 * ce que l'app lui propose en exemple. C'est l'**écriture en base** qui est
 * internationale.
 *
 * Ce que ce choix règle d'un coup :
 * - le **client** voit un numéro composable depuis n'importe où, et le lien
 *   `tel:` de `phone_launcher.dart` fonctionne hors d'Algérie ;
 * - l'export CRM n'a plus rien à dériver — c'est le champ que le rapprochement
 *   d'appels attend (`docs/SPEC_INTEGRATION_ECHANGOCRM.md` §6) ;
 * - une seule écriture existe en base, donc une seule à comparer.
 *
 * ⚠️ **Et il ne casse pas la recherche admin**, contrairement à ce que craignait
 * une version antérieure de ce commentaire : depuis le 2026-08-15 elle compare
 * les **chiffres** (`chiffresDeRecherche`), pas la chaîne. C'est précisément ce
 * qui rend la forme stockée libre de changer.
 */

/** Décision produit : le pilote est algérien, le reste est une extension. */
export const PAYS_PAR_DEFAUT: CountryCode = 'DZ';

export interface TelephoneNormalise {
  /** Forme stockée et affichée, sans espaces : `0555000101`. */
  national: string;
  /** Forme dérivée, pour l'export et les liens `tel:` : `+213555000101`. */
  e164: string;
  pays: CountryCode;
}

/**
 * ⚠️ **Le pays déclaré fait autorité, et c'est tout l'intérêt de la colonne.**
 * `parsePhoneNumberFromString('+971551234567', 'DZ')` rend un numéro **valide**
 * : l'indicatif explicite l'emporte sur l'indication de pays, qui n'est qu'un
 * défaut de lecture. Sans la vérification `country === pays`, un numéro
 * émirati saisi sous « Algérie » serait accepté et stocké sous un pays qu'il
 * n'a pas — la colonne deviendrait décorative, et l'unicité composite
 * `(pays, telephone)` cesserait de vouloir dire quelque chose.
 *
 * Rend `null` sur tout ce qui n'est pas un numéro valide **du pays déclaré** :
 * pas de repli, pas de « à peu près » (règle #29).
 */
export function normaliserTelephone(
  saisie: string,
  pays: CountryCode = PAYS_PAR_DEFAUT,
): TelephoneNormalise | null {
  if (typeof saisie !== 'string' || saisie.trim() === '') {
    return null;
  }
  const parse = parsePhoneNumberFromString(saisie.trim(), pays);
  if (!parse || !parse.isValid() || parse.country !== pays) {
    return null;
  }
  return {
    // `formatNational` rend une forme espacée (`0555 00 01 01`) : on ne garde
    // que les chiffres, pour que la comparaison d'unicité et la recherche admin
    // portent sur une chaîne unique et prévisible.
    national: parse.formatNational().replace(/\D/g, ''),
    e164: parse.number,
    pays,
  };
}

/**
 * Nombre de chiffres de fin comparés pour **retrouver** un numéro, par
 * opposition à le valider.
 *
 * Neuf, parce qu'un mobile algérien s'écrit indifféremment `0555000101`,
 * `+213555000101` ou `00213555000101` : ce qui reste stable, ce sont les neuf
 * derniers chiffres. C'est le même choix, et le même chiffre, que le
 * rapprochement d'appels du CRM (`call_tracker_log.py`) — deux règles de
 * recherche différentes sur les mêmes numéros finiraient par ne pas trouver les
 * mêmes gens.
 */
export const CHIFFRES_SIGNIFICATIFS = 9;

/**
 * Les chiffres significatifs d'une **recherche**, ou `null` si la saisie n'a
 * pas l'air d'un numéro.
 *
 * ⚠️ **Rien à voir avec `normaliserTelephone`, et les confondre serait une
 * faute.** Celle-ci valide et rejette ; celle-là doit trouver, y compris sur
 * une saisie partielle et sans savoir de quel pays il s'agit. Un admin qui tape
 * `+213555000101` et un autre qui tape `0555000101` cherchent le même
 * commerçant — c'était vrai avant la normalisation du parc, ça doit le rester
 * après.
 *
 * Le seuil de 6 chiffres évite qu'une recherche par nom contenant deux ou trois
 * chiffres (« Boutique 22 ») ne se mette à balayer les téléphones.
 */
export function chiffresDeRecherche(saisie: string): string | null {
  const chiffres = (saisie ?? '').replace(/\D/g, '');
  if (chiffres.length < 6) return null;
  return chiffres.slice(-CHIFFRES_SIGNIFICATIFS);
}

/**
 * Le pays d'une saisie, avec son défaut résolu **une seule fois**.
 *
 * Recopier `dto.pays ?? 'DZ'` à chaque site d'appel ferait vivre la décision
 * produit « le pilote est algérien » dans autant d'endroits qu'il y a de
 * routes — celui qu'on oublierait rendrait un `undefined` à la bibliothèque,
 * qui refuserait alors tout numéro national sans le moindre message parlant.
 */
export function paysOuDefaut(pays?: string | null): CountryCode {
  return (pays as CountryCode) || PAYS_PAR_DEFAUT;
}

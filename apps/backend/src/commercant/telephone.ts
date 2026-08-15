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
 * La forme stockée est la **forme nationale**, celle que le commerçant connaît
 * et lit sur sa devanture (`0555000101`). L'E.164 est **dérivé** — pour l'export
 * CRM, où il conditionne le rapprochement des appels entrants
 * (`docs/SPEC_INTEGRATION_ECHANGOCRM.md` §6). Stocker l'E.164 à la place aurait
 * cassé la recherche `ILIKE` de l'écran admin, où l'on tape ce qu'on lit.
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

import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { LoginCommercantDto } from './dto/login-commercant.dto';
import {
  chiffresDeRecherche,
  normaliserTelephone,
  PAYS_PAR_DEFAUT,
  paysOuDefaut,
} from './telephone';

/**
 * Règle #28 : autant de cas qui doivent **échouer** que de cas qui passent.
 * Un normaliseur qui accepte tout ne normalise rien.
 */

describe('normaliserTelephone', () => {
  it('rend la même forme stockée pour toutes les écritures d’un même numéro', () => {
    // ⚠️ **C'est LE défaut que ce module ferme**, et il existait en production :
    // `0555000101` et `+213555000101` étaient deux chaînes distinctes, donc deux
    // comptes possibles pour un même commerçant, et une connexion refusée à qui
    // saisissait l'autre forme que la sienne.
    const ecritures = [
      '0555000101',
      '+213555000101',
      '00213555000101',
      '0555 00 01 01',
      '  0555-00-01-01  ',
    ];
    const formes = ecritures.map((e) => normaliserTelephone(e, 'DZ')?.national);
    expect(new Set(formes).size).toBe(1);
    expect(formes[0]).toBe('0555000101');
  });

  it('dérive l’E.164 attendu par le rapprochement d’appels du CRM', () => {
    expect(normaliserTelephone('0555000101', 'DZ')?.e164).toBe('+213555000101');
  });

  it('refuse un numéro d’un AUTRE pays que celui déclaré', () => {
    // La bibliothèque accepte volontiers `+971…` avec une indication `DZ` :
    // l'indicatif explicite l'emporte sur l'indication de pays. Sans ce refus,
    // la colonne `pays` serait décorative et l'unicité composite ne voudrait
    // plus rien dire.
    expect(normaliserTelephone('+971551234567', 'DZ')).toBeNull();
    expect(normaliserTelephone('+971551234567', 'AE')?.e164).toBe(
      '+971551234567',
    );
  });

  it.each([
    ['vide', ''],
    ['espaces', '   '],
    ['trop court', '0555'],
    ['lettres', 'zéro cinq cinq'],
    ['indicatif seul', '+213'],
    ['chiffres surnuméraires', '05550001010000'],
  ])('refuse %s', (_libelle, saisie) => {
    expect(normaliserTelephone(saisie, 'DZ')).toBeNull();
  });

  it('applique le pays par défaut sans le deviner', () => {
    expect(paysOuDefaut(undefined)).toBe(PAYS_PAR_DEFAUT);
    expect(paysOuDefaut('')).toBe(PAYS_PAR_DEFAUT);
    expect(paysOuDefaut('AE')).toBe('AE');
    expect(normaliserTelephone('0555000101')?.pays).toBe(PAYS_PAR_DEFAUT);
  });
});

describe('les trois comportements attendus du produit (2026-08-15)', () => {
  it('1. le pays par défaut est l’Algérie, sans le deviner', () => {
    expect(PAYS_PAR_DEFAUT).toBe('DZ');
    expect(normaliserTelephone('0555000101')?.pays).toBe('DZ');
    expect(normaliserTelephone('0555000101')?.e164).toBe('+213555000101');
  });

  it('2. le zéro de tête disparaît : 0555000101 est stocké +213555000101', () => {
    const normalise = normaliserTelephone('0555000101', 'DZ');
    // C'est `e164` que le service écrit en base depuis le 2026-08-15.
    expect(normalise?.e164).toBe('+213555000101');
    expect(normalise?.e164.startsWith('+2130')).toBe(false);
  });

  it('3. la forme servie au client est composable de partout', () => {
    // Le client voit ce que la base contient : l'API publique ne reformate
    // rien. Un `tel:+213555000101` fonctionne depuis n'importe quel pays, un
    // `tel:0555000101` seulement depuis l'Algérie.
    expect(normaliserTelephone('0555000101', 'DZ')?.e164).toMatch(
      /^\+\d{6,15}$/,
    );
  });

  it('et la saisie reste nationale : l’exemple montré ne change pas', () => {
    // ⚠️ Ce que la base stocke n'est PAS ce que le commerçant tape. Confondre
    // les deux ferait afficher « +213555000101 » en indice de saisie, donc
    // ressaisir l'indicatif dans un champ qui a déjà un sélecteur de pays.
    expect(normaliserTelephone('0555000101', 'DZ')?.national).toBe(
      '0555000101',
    );
  });
});

describe('chiffresDeRecherche', () => {
  it('rend la même clé pour toutes les écritures d’un numéro', () => {
    // C'est ce qui permet à un admin de retrouver un commerçant qu'il connaît
    // en `+213…` alors que la base stocke `0…` depuis la normalisation du parc.
    const clefs = [
      '0555000101',
      '+213555000101',
      '00213555000101',
      '213 555 00 01 01',
      '0555 00 01 01',
    ].map(chiffresDeRecherche);
    expect(new Set(clefs).size).toBe(1);
    expect(clefs[0]).toBe('555000101');
  });

  it('ignore une recherche qui n’a pas l’air d’un numéro', () => {
    // ⚠️ Le cas qui doit ÉCHOUER : sans ce seuil, chercher « Boutique 22 » se
    // mettrait à balayer les téléphones sur « 22 » et rendrait n'importe quoi.
    expect(chiffresDeRecherche('Boutique 22')).toBeNull();
    expect(chiffresDeRecherche('Alimentation')).toBeNull();
    expect(chiffresDeRecherche('')).toBeNull();
    expect(chiffresDeRecherche('12345')).toBeNull();
  });

  it('accepte une recherche partielle dès six chiffres', () => {
    expect(chiffresDeRecherche('555000')).toBe('555000');
    expect(chiffresDeRecherche('0555000101')).toBe('555000101');
  });
});

describe('le DTO de connexion', () => {
  function erreursDe(charge: Record<string, unknown>): string[] {
    const dto = plainToInstance(LoginCommercantDto, charge);
    return validateSync(dto).map((e) => e.property);
  }

  it('accepte les deux formes du numéro national', () => {
    expect(erreursDe({ telephone: '0555000101', pin: '123456' })).toEqual([]);
    expect(erreursDe({ telephone: '+213555000101', pin: '123456' })).toEqual(
      [],
    );
  });

  it('accepte un numéro étranger quand le pays le dit', () => {
    expect(
      erreursDe({ telephone: '+971551234567', pays: 'AE', pin: '123456' }),
    ).toEqual([]);
  });

  it('refuse ce même numéro sous le pays par défaut', () => {
    // Le validateur d'origine (`@IsPhoneNumber('DZ')`) figeait la région à la
    // compilation : il aurait continué de refuser TOUT numéro non algérien, sur
    // un produit qui venait d'annoncer le contraire.
    expect(erreursDe({ telephone: '+971551234567', pin: '123456' })).toEqual([
      'telephone',
    ]);
  });

  it('refuse un pays qui n’est pas un code ISO', () => {
    expect(
      erreursDe({ telephone: '0555000101', pays: 'Algérie', pin: '123456' }),
    ).toContain('pays');
  });

  it('refuse une saisie vide', () => {
    expect(erreursDe({ telephone: '', pin: '123456' })).toContain('telephone');
  });
});

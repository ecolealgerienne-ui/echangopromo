import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { LoginCommercantDto } from './dto/login-commercant.dto';
import {
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

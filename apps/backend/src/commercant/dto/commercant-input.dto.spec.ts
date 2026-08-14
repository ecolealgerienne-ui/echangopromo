import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import {
  ADRESSE_MAX_LENGTH,
  NOM_MAX_LENGTH,
} from '../entities/commercant.entity';
import { CreateCommercantByAgentDto } from './create-commercant-by-agent.dto';
import { RegisterCommercantDto } from './register-commercant.dto';
import { UpdateCommercantDto } from './update-commercant.dto';

/**
 * **Ce que ce banc prouve : que les bornes de `nom` et `adresse` savent
 * REFUSER.** Une borne non éprouvée ne compte pas (règle 34) — et celle-ci
 * était absente jusqu'au 2026-08-13.
 *
 * ⚠️ **`adresse` mérite ce banc pour une raison de calendrier**, pas parce
 * qu'un champ texte serait dangereux en soi. Les deux champs étaient sans
 * plafond depuis toujours ; ce qui a changé, c'est que la suppression de
 * `commune`/`wilaya` a fait d'`adresse` **le seul repère de lieu en texte
 * libre** du produit. Elle est servie au client sur la fiche promo, cherchée
 * par l'admin, et n'a plus aucun référentiel derrière elle.
 *
 * ⚠️ **La borne vit dans le DTO, pas dans la colonne**, et c'est délibéré :
 * `varchar` sans longueur n'oppose aucune limite, il n'y a donc rien à
 * refléter. Voir l'en-tête de `NOM_MAX_LENGTH` dans l'entité pour le
 * raisonnement complet. Conséquence directe pour ce fichier : **il est le seul
 * endroit qui puisse constater le refus** — aucune erreur Postgres ne viendra
 * en renfort si le décorateur disparaît.
 *
 * ⚠️ Autant de cas qui doivent ÉCHOUER que de cas qui passent (règle 28), et
 * les trois DTO sont éprouvées séparément : elles portent les mêmes bornes sans
 * qu'aucun code ne les relie. Un `@MaxLength` oublié sur l'une des trois
 * laisserait une porte ouverte que les deux autres masqueraient (règle 30 — si
 * l'une change, les autres doivent changer).
 */
describe('Bornes de saisie du commerçant — nom et adresse', () => {
  const nominal = {
    telephone: '+213555000101',
    nom: 'Épicerie du Centre',
    adresse: 'Rue des Frères Bouadjadj',
    categorie: 'alimentation',
    pin: '654321',
    acceptedTerms: true,
    // ⚠️ Obligatoires pour `CreateCommercantByAgentDto` depuis le 2026-08-12 :
    // une fiche créée en tournée sans position est invisible de tous. Absentes
    // du jeu nominal, elles faisaient rendre `['latitude','longitude']` aux
    // trois cas « doit passer » — le banc accusait la borne d'un refus qui
    // venait d'ailleurs (règle 38, en miniature).
    latitude: 34.6714,
    longitude: 3.263,
  };

  /** `Type` est la classe de DTO, `patch` ce qu'on fait varier. */
  const erreursDe = (
    Type: new () => object,
    patch: Record<string, unknown>,
  ): string[] => {
    const dto = plainToInstance(Type, { ...nominal, ...patch });
    return validateSync(dto).map((e) => e.property);
  };

  const cas: [string, new () => object][] = [
    ['RegisterCommercantDto', RegisterCommercantDto],
    ['CreateCommercantByAgentDto', CreateCommercantByAgentDto],
    ['UpdateCommercantDto', UpdateCommercantDto],
  ];

  describe.each(cas)('%s', (_libelle, Type) => {
    // ── Doivent PASSER ──────────────────────────────────────────────────────

    it('accepte une saisie nominale', () => {
      expect(erreursDe(Type, {})).toEqual([]);
    });

    it('accepte un nom exactement à la borne', () => {
      expect(erreursDe(Type, { nom: 'n'.repeat(NOM_MAX_LENGTH) })).toEqual([]);
    });

    it('accepte une adresse exactement à la borne', () => {
      expect(
        erreursDe(Type, { adresse: 'a'.repeat(ADRESSE_MAX_LENGTH) }),
      ).toEqual([]);
    });

    // ── Doivent REFUSER ─────────────────────────────────────────────────────

    it('refuse un nom d’un caractère de trop', () => {
      expect(
        erreursDe(Type, { nom: 'n'.repeat(NOM_MAX_LENGTH + 1) }),
      ).toContain('nom');
    });

    it('refuse une adresse d’un caractère de trop', () => {
      expect(
        erreursDe(Type, { adresse: 'a'.repeat(ADRESSE_MAX_LENGTH + 1) }),
      ).toContain('adresse');
    });

    // ⚠️ **Le cas qui compte vraiment.** Sans plafond, c'est exactement ce qui
    // arrivait en base : une adresse d'un mégaoctet, acceptée, servie ensuite
    // sur la fiche promo de chaque client. Le refus doit tenir aux ordres de
    // grandeur, pas seulement à la borne + 1.
    it('refuse une adresse absurde', () => {
      expect(erreursDe(Type, { adresse: 'a'.repeat(1_000_000) })).toContain(
        'adresse',
      );
    });

    // ⚠️ La borne haute ne doit pas avoir mangé la borne basse : deux
    // décorateurs sur le même champ, et c'est le second qu'on oublie de
    // vérifier.
    it('refuse toujours un nom trop court', () => {
      expect(erreursDe(Type, { nom: 'a' })).toContain('nom');
    });
  });

  // ── Ce qui distingue les trois, et qu'il ne faut pas confondre ────────────

  it('UpdateCommercantDto accepte l’absence de nom et d’adresse', () => {
    // Édition partielle : ne pas envoyer un champ n'est pas l'effacer. Un
    // `@MaxLength` sur un champ absent ne doit rien lever — sans quoi le
    // moindre `PATCH` de position exigerait de renvoyer tout le profil.
    const dto = plainToInstance(UpdateCommercantDto, { categorie: 'autre' });
    expect(validateSync(dto)).toEqual([]);
  });
});

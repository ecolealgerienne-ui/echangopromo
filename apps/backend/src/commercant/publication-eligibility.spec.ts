import { HttpStatus } from '@nestjs/common';
import { ErrorCode } from '../common/errors/error-code.enum';
import {
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';
import {
  evaluerPublication,
  exceptionDeRefus,
  FaitsAgregat,
  FaitsFiche,
  MotifBlocagePublication,
  regleCompteApplicable,
  regleFicheApplicable,
  regleParMotif,
  REGLES_PUBLICATION,
} from './publication-eligibility';

/**
 * Le contrôle d'équivalence du lot 0 (`docs/SPEC_INTEGRATION_ECHANGOCRM.md`
 * §5.1).
 *
 * La spécification a d'abord demandé « une fonction unique appelée par les
 * gardes et par l'export ». C'est impossible : les gardes lèvent par ligne, le
 * plafond dépend d'un agrégat. Ce qui est unique, c'est la table — et **un
 * commentaire ne peut pas échouer** (règle #30). C'est donc ce banc, et lui
 * seul, qui tient l'invariant : chaque motif doit être rendu à l'identique par
 * les deux rendus, dans le même ordre, avec le même code et le même statut.
 *
 * Règle #28 : autant de cas qui doivent **passer** que de cas qui doivent
 * **bloquer**. Un banc qui ne montre que des refus n'a prouvé que sa capacité à
 * dire non.
 */

const FICHE_SAINE: FaitsFiche = {
  deletedAt: null,
  suspendedAt: null,
  originVerification: CommercantOriginVerification.CONFIRME_AGENT,
  registreStatus: null,
  profilePendingReview: false,
  latitude: 34.67,
  longitude: 3.25,
};

const AGREGAT_SAIN: FaitsAgregat = {
  promosEnLigne: 2,
  plafondEffectif: 5,
  creations24h: 1,
  quotaCreation24h: 5,
  acteurDeConfiance: false,
};

/** Le déclencheur minimal de chaque motif, à partir d'un commerçant sain. */
const DECLENCHEURS: Record<
  MotifBlocagePublication,
  Partial<FaitsFiche & FaitsAgregat>
> = {
  [MotifBlocagePublication.COMPTE_SUPPRIME]: {
    deletedAt: new Date('2026-08-01T10:00:00Z'),
  },
  [MotifBlocagePublication.COMPTE_SUSPENDU]: {
    suspendedAt: new Date('2026-08-01T10:00:00Z'),
  },
  [MotifBlocagePublication.REGISTRE_ABSENT]: {
    originVerification: CommercantOriginVerification.AUTO_INSCRIT,
    registreStatus: null,
  },
  [MotifBlocagePublication.REGISTRE_EN_ATTENTE]: {
    originVerification: CommercantOriginVerification.AUTO_INSCRIT,
    registreStatus: RegistreStatus.EN_ATTENTE,
  },
  [MotifBlocagePublication.REGISTRE_REJETE]: {
    originVerification: CommercantOriginVerification.AUTO_INSCRIT,
    registreStatus: RegistreStatus.REJETE,
  },
  [MotifBlocagePublication.PROFIL_EN_REVUE]: { profilePendingReview: true },
  [MotifBlocagePublication.POSITION_ABSENTE]: { latitude: null },
  [MotifBlocagePublication.PLAFOND_ATTEINT]: { promosEnLigne: 5 },
  [MotifBlocagePublication.QUOTA_CREATION_24H]: { creations24h: 5 },
};

function faits(
  patch: Partial<FaitsFiche & FaitsAgregat> = {},
): FaitsFiche & FaitsAgregat {
  return { ...FICHE_SAINE, ...AGREGAT_SAIN, ...patch };
}

describe('table des motifs de blocage', () => {
  it('couvre exactement les motifs de l’enum, sans doublon', () => {
    const declares = REGLES_PUBLICATION.map((r) => r.motif);
    expect(new Set(declares).size).toBe(declares.length);
    expect(declares.sort()).toEqual(
      Object.values(MotifBlocagePublication).sort(),
    );
  });

  it('a un cas de test pour chaque règle', () => {
    // Sans ceci, ajouter une règle sans l'éprouver passerait inaperçu : le banc
    // resterait vert sur une table qu'il ne couvre plus entièrement.
    for (const regle of REGLES_PUBLICATION) {
      expect(DECLENCHEURS[regle.motif]).toBeDefined();
    }
  });

  it('rend la règle demandée, et refuse un motif inconnu', () => {
    expect(regleParMotif(MotifBlocagePublication.PLAFOND_ATTEINT).code).toBe(
      ErrorCode.PROMO_ACTIVE_CAP_REACHED,
    );
    expect(() =>
      regleParMotif('motif_qui_n_existe_pas' as MotifBlocagePublication),
    ).toThrow(/inconnu/);
  });
});

describe('ce qui NE bloque PAS', () => {
  it('laisse publier un commerçant sain', () => {
    expect(evaluerPublication(faits())).toEqual({
      peutPublier: true,
      motif: null,
    });
  });

  it('accepte une position sur le méridien de Greenwich', () => {
    // `!longitude` refuserait `0`, qui est une coordonnée parfaitement
    // légitime — même piège que `configNumber`.
    expect(
      evaluerPublication(faits({ latitude: 0, longitude: 0 })).peutPublier,
    ).toBe(true);
  });

  it('n’exige pas de registre d’un commerçant confirmé par un agent', () => {
    // Le cas le plus fréquent du pilote : `registreStatus` est `null` pour tout
    // compte créé par un agent, et ce n'est pas un blocage.
    expect(
      evaluerPublication(
        faits({
          originVerification: CommercantOriginVerification.CONFIRME_AGENT,
          registreStatus: null,
        }),
      ).peutPublier,
    ).toBe(true);
  });

  it('accepte un auto-inscrit dont le registre est validé', () => {
    expect(
      evaluerPublication(
        faits({
          originVerification: CommercantOriginVerification.AUTO_INSCRIT,
          registreStatus: RegistreStatus.VALIDE,
        }),
      ).peutPublier,
    ).toBe(true);
  });

  it('accepte le dernier emplacement libre et la dernière création', () => {
    // Les deux bornes sont des `>=` : à plafond - 1, il reste exactement un
    // geste possible. Un `>` aurait laissé publier une promo de trop.
    expect(
      evaluerPublication(faits({ promosEnLigne: 4, plafondEffectif: 5 }))
        .peutPublier,
    ).toBe(true);
    expect(
      evaluerPublication(faits({ creations24h: 4, quotaCreation24h: 5 }))
        .peutPublier,
    ).toBe(true);
  });

  it('exempte l’agent du quota de créations, mais jamais du plafond', () => {
    expect(
      evaluerPublication(faits({ creations24h: 99, acteurDeConfiance: true }))
        .peutPublier,
    ).toBe(true);
    expect(
      evaluerPublication(faits({ promosEnLigne: 5, acteurDeConfiance: true }))
        .motif,
    ).toBe(MotifBlocagePublication.PLAFOND_ATTEINT);
  });
});

describe('ce qui bloque', () => {
  it.each(Object.values(MotifBlocagePublication))(
    'rend le motif %s quand il est seul à s’appliquer',
    (motif) => {
      const resultat = evaluerPublication(faits(DECLENCHEURS[motif]));
      expect(resultat).toEqual({ peutPublier: false, motif });
    },
  );
});

describe('l’ordre des motifs', () => {
  it('annonce la suppression avant la suspension', () => {
    expect(
      evaluerPublication(
        faits({
          ...DECLENCHEURS[MotifBlocagePublication.COMPTE_SUPPRIME],
          ...DECLENCHEURS[MotifBlocagePublication.COMPTE_SUSPENDU],
        }),
      ).motif,
    ).toBe(MotifBlocagePublication.COMPTE_SUPPRIME);
  });

  it('annonce le compte mort avant la donnée manquante', () => {
    // Un commerçant suspendu ET sans position ET au plafond doit s'entendre
    // dire qu'il est suspendu : l'envoyer poser sa position serait lui faire
    // réparer une fiche qui ne publiera de toute façon pas.
    expect(
      evaluerPublication(
        faits({
          suspendedAt: new Date('2026-08-01T10:00:00Z'),
          latitude: null,
          promosEnLigne: 5,
        }),
      ).motif,
    ).toBe(MotifBlocagePublication.COMPTE_SUSPENDU);
  });

  it('annonce la fiche avant les agrégats, et le plafond avant le quota', () => {
    expect(
      evaluerPublication(
        faits({ profilePendingReview: true, promosEnLigne: 5 }),
      ).motif,
    ).toBe(MotifBlocagePublication.PROFIL_EN_REVUE);
    expect(
      evaluerPublication(faits({ promosEnLigne: 5, creations24h: 5 })).motif,
    ).toBe(MotifBlocagePublication.PLAFOND_ATTEINT);
  });
});

describe('équivalence entre le rendu « garde » et le rendu « export »', () => {
  const motifsFiche = REGLES_PUBLICATION.filter(
    (r) => r.portee === 'fiche',
  ).map((r) => r.motif);

  it.each(motifsFiche)(
    'la garde de fiche et l’export désignent le même motif pour %s',
    (motif) => {
      const contexte = faits(DECLENCHEURS[motif]);
      expect(regleFicheApplicable(contexte)?.motif).toBe(
        evaluerPublication(contexte).motif,
      );
    },
  );

  it('la garde de fiche ignore les motifs d’agrégat', () => {
    // Elle n'a pas les comptages sous la main : elle doit se taire, pas
    // conclure. C'est l'export, lui, qui les évalue.
    const contexte = faits({ promosEnLigne: 5, creations24h: 5 });
    expect(regleFicheApplicable(contexte)).toBeNull();
    expect(evaluerPublication(contexte).peutPublier).toBe(false);
  });

  it.each(motifsFiche)(
    'l’exception porte le code et le statut de la table pour %s',
    (motif) => {
      const regle = regleParMotif(motif);
      const exception = exceptionDeRefus(regle, faits(DECLENCHEURS[motif]));
      const corps = exception.getResponse() as { code: ErrorCode };
      expect(corps.code).toBe(regle.code);
      expect(exception.getStatus()).toBe(
        regle.statut === 'forbidden'
          ? HttpStatus.FORBIDDEN
          : HttpStatus.BAD_REQUEST,
      );
    },
  );

  it('les trois états de registre partagent un seul code d’erreur', () => {
    // Trois motifs pour le CRM — qui doit distinguer « il n'a rien envoyé » de
    // « nous n'avons pas traité » — mais un seul message pour le commerçant,
    // qui n'a qu'un geste à faire. Multiplier les codes imposerait trois
    // entrées dans chacun des trois mappings mobile (règle #26) pour rien.
    const codes = [
      MotifBlocagePublication.REGISTRE_ABSENT,
      MotifBlocagePublication.REGISTRE_EN_ATTENTE,
      MotifBlocagePublication.REGISTRE_REJETE,
    ].map((m) => regleParMotif(m).code);
    expect(new Set(codes).size).toBe(1);
    expect(codes[0]).toBe(ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED);
  });
});

describe('la garde du brouillon', () => {
  it('ne retient que le compte supprimé ou suspendu', () => {
    expect(
      regleCompteApplicable(
        faits(DECLENCHEURS[MotifBlocagePublication.COMPTE_SUSPENDU]),
      )?.motif,
    ).toBe(MotifBlocagePublication.COMPTE_SUSPENDU);
  });

  it.each([
    MotifBlocagePublication.REGISTRE_EN_ATTENTE,
    MotifBlocagePublication.PROFIL_EN_REVUE,
    MotifBlocagePublication.POSITION_ABSENTE,
  ])('laisse préparer un brouillon malgré %s', (motif) => {
    // Le défaut de la revue 2026-08-05 : les gardes de publication posées pour
    // tout le monde refusaient aussi « Enregistrer comme brouillon », avec un
    // message parlant de publier sur un geste qui ne publie pas.
    const contexte = faits(DECLENCHEURS[motif]);
    expect(regleCompteApplicable(contexte)).toBeNull();
    expect(evaluerPublication(contexte).peutPublier).toBe(false);
  });
});

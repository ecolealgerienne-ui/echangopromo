import { HttpException } from '@nestjs/common';
import { PromoLifecycleStatus, PromoModerationStatus } from '../promo/entities/promo.entity';
import type { Promo } from '../promo/entities/promo.entity';
import { UpdateHighlightDto } from './dto/update-highlight.dto';
import type { Highlight } from './entities/highlight.entity';
import { HighlightService } from './highlight.service';

/**
 * Couvre les règles métier du bandeau d'accueil, pas le câblage NestJS —
 * le service est instancié à la main avec des doubles, comme
 * `jwt-auth.guard.spec.ts`.
 *
 * Ces tests existent parce que la sémantique du patch partiel a été livrée
 * cassée une première fois : `'champ' in dto` est toujours vrai sur un DTO
 * transformé par `ValidationPipe` (TypeScript crée une propriété propre
 * valant `undefined` pour chaque champ déclaré, cible ES2023), si bien
 * qu'une simple bascule visible/masqué effaçait la promo et l'image de la
 * diapositive. D'où l'usage de `new UpdateHighlightDto()` ci-dessous plutôt
 * qu'un objet littéral : c'est la forme réelle reçue par le service, et
 * c'est la seule qui rende cette régression détectable.
 */

type Repo = {
  find: jest.Mock;
  findOne: jest.Mock;
  save: jest.Mock;
  delete: jest.Mock;
};

function makeHighlight(overrides: Partial<Highlight> = {}): Highlight {
  return {
    id: 'h1',
    position: 1,
    active: true,
    promo: null,
    promoId: 'p1',
    imageKey: 'highlight-images/a1/photo.jpg',
    titre: 'Titre choisi',
    sousTitre: 'Sous-titre choisi',
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
    // `as unknown as` assumé : ces doubles ne portent que les champs dont
    // les règles testées se servent, pas l'entité complète.
  } as unknown as Highlight;
}

function makePromo(overrides: Partial<Promo> = {}): Promo {
  return {
    id: 'p1',
    commercantId: 'c1',
    commercant: { id: 'c1', nom: 'Chez Ali' },
    description: 'Jus de fruits',
    prixAvant: '200.00',
    prixApres: '150.00',
    photoKeys: ['promo-photos/c1/photo.jpg'],
    thumbnailKey: null,
    lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
    moderationStatus: PromoModerationStatus.NORMALE,
    ...overrides,
  } as unknown as Promo;
}

async function errorCode(promise: Promise<unknown>): Promise<string | undefined> {
  try {
    await promise;
    return undefined;
  } catch (error) {
    const response = (error as HttpException).getResponse();
    return typeof response === 'object' && response !== null
      ? (response as { code?: string }).code
      : undefined;
  }
}

/**
 * Le premier argument du premier appel à `save`, **typé**.
 *
 * ⚠️ `jest.Mock.mock.calls` est `any` : l'indexer directement déclenche
 * `no-unsafe-member-access`, et c'est ce qui faisait échouer `npm run lint` sur
 * trois assertions de ce fichier (trouvé le 2026-08-05, au premier lancement de
 * la commande). Un accès typé une fois vaut mieux que trois `eslint-disable`,
 * qui seraient trois occasions d'en oublier un.
 */
function premierSave(repo: Repo): Highlight {
  const appels = repo.save.mock.calls as unknown as [Highlight][];
  return appels[0][0];
}

describe('HighlightService', () => {
  let highlights: Repo;
  let promoService: {
    findVisibleByIds: jest.Mock;
    findActiveForClient: jest.Mock;
    findByIdOrFail: jest.Mock;
  };
  let storageService: { deleteObject: jest.Mock };
  let service: HighlightService;

  beforeEach(() => {
    highlights = {
      find: jest.fn(),
      findOne: jest.fn(),
      save: jest.fn((entity: unknown) => Promise.resolve(entity)),
      delete: jest.fn(),
    };
    promoService = {
      findVisibleByIds: jest.fn().mockResolvedValue([]),
      findActiveForClient: jest.fn(),
      findByIdOrFail: jest.fn().mockResolvedValue(makePromo()),
    };
    storageService = { deleteObject: jest.fn().mockResolvedValue(undefined) };
    service = new HighlightService(
      highlights as never,
      promoService as never,
      storageService as never,
    );
  });

  describe('update', () => {
    it("ne touche ni à la promo ni à l'image quand seule la visibilité change", async () => {
      const existing = makeHighlight();
      highlights.findOne.mockResolvedValue(existing);
      promoService.findVisibleByIds.mockResolvedValue([makePromo()]);

      // Forme réelle produite par `ValidationPipe` : tous les champs
      // déclarés existent, seuls ceux réellement envoyés sont renseignés.
      const dto = Object.assign(new UpdateHighlightDto(), { active: false });
      await service.update('h1', dto);

      const saved = premierSave(highlights);
      expect(saved.active).toBe(false);
      expect(saved.promoId).toBe('p1');
      expect(saved.imageKey).toBe('highlight-images/a1/photo.jpg');
      expect(saved.titre).toBe('Titre choisi');
      expect(saved.sousTitre).toBe('Sous-titre choisi');
      expect(storageService.deleteObject).not.toHaveBeenCalled();
    });

    it('retire la promo ciblée sur `clearPromo`, sans toucher à l\'image', async () => {
      highlights.findOne.mockResolvedValue(makeHighlight());

      const dto = Object.assign(new UpdateHighlightDto(), { clearPromo: true });
      await service.update('h1', dto);

      const saved = premierSave(highlights);
      expect(saved.promoId).toBeNull();
      expect(saved.imageKey).toBe('highlight-images/a1/photo.jpg');
    });

    it("supprime l'objet S3 devenu orphelin quand l'image est retirée", async () => {
      highlights.findOne.mockResolvedValue(makeHighlight());

      const dto = Object.assign(new UpdateHighlightDto(), { clearImage: true });
      await service.update('h1', dto);

      expect(storageService.deleteObject).toHaveBeenCalledWith(
        'highlight-images/a1/photo.jpg',
      );
    });

    it('traite une chaîne vide comme un effacement de texte', async () => {
      highlights.findOne.mockResolvedValue(makeHighlight());

      const dto = Object.assign(new UpdateHighlightDto(), { titre: '   ' });
      await service.update('h1', dto);

      expect(premierSave(highlights).titre).toBeNull();
    });

    it('refuse une diapositive qui ne montrerait plus rien', async () => {
      highlights.findOne.mockResolvedValue(makeHighlight({ imageKey: null }));

      const dto = Object.assign(new UpdateHighlightDto(), { clearPromo: true });
      expect(await errorCode(service.update('h1', dto))).toBe('HIGHLIGHT_EMPTY_CONTENT');
      expect(highlights.save).not.toHaveBeenCalled();
    });
  });

  describe('findForClient', () => {
    it('retombe sur le classement calculé quand aucune curation n\'existe', async () => {
      highlights.find.mockResolvedValue([]);
      promoService.findActiveForClient.mockResolvedValue({
        items: [makePromo()],
        total: 1,
        page: 1,
        limit: 8,
      });

      const slides = await service.findForClient();

      expect(slides).toHaveLength(1);
      expect(slides[0].curated).toBe(false);
      // Identifiant préfixé : il ne désigne aucune ligne `highlight`.
      expect(slides[0].id).toBe('auto-p1');
    });

    it('écarte une diapositive dont la promo n\'est plus visible, et bascule sur le repli si plus rien ne reste', async () => {
      highlights.find.mockResolvedValue([makeHighlight({ imageKey: null })]);
      promoService.findVisibleByIds.mockResolvedValue([]);
      promoService.findActiveForClient.mockResolvedValue({
        items: [makePromo({ id: 'p9' })],
        total: 1,
        page: 1,
        limit: 8,
      });

      const slides = await service.findForClient();

      expect(slides).toHaveLength(1);
      expect(slides[0].curated).toBe(false);
    });

    it('garde une affiche sans promo tant qu\'elle porte une image', async () => {
      highlights.find.mockResolvedValue([
        makeHighlight({ promoId: null, titre: 'Ramadan' }),
      ]);

      const slides = await service.findForClient();

      expect(slides).toHaveLength(1);
      expect(slides[0].curated).toBe(true);
      expect(slides[0].promo).toBeNull();
      expect(promoService.findActiveForClient).not.toHaveBeenCalled();
    });
  });

  describe('reorder', () => {
    it('refuse un ordre partiel, qui laisserait deux diapositives sur la même position', async () => {
      highlights.find.mockResolvedValue([{ id: 'h1' }, { id: 'h2' }]);

      expect(await errorCode(service.reorder({ ids: ['h1'] }))).toBe(
        'HIGHLIGHT_REORDER_MISMATCH',
      );
    });

    it('refuse un identifiant en double', async () => {
      highlights.find.mockResolvedValue([{ id: 'h1' }, { id: 'h2' }]);

      expect(await errorCode(service.reorder({ ids: ['h1', 'h1'] }))).toBe(
        'HIGHLIGHT_REORDER_MISMATCH',
      );
    });
  });
});

import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { PRIX_MAX } from '../entities/promo.entity';
import { CreatePromoDto } from './create-promo.dto';

/**
 * **Ce que ce banc prouve : que la validation d'entrée sait REFUSER.**
 *
 * Un DTO décoré ne vaut que si `ValidationPipe` le refuse effectivement — et
 * rien ne le vérifiait. Les deux cas au cœur du fichier sont ceux trouvés le
 * 2026-08-05 : un prix au-delà de la précision de la colonne (`numeric(10,2)`,
 * qui sortait en `500` Postgres au lieu d'un refus de validation) et les
 * champs numériques venus du réseau en général.
 *
 * ⚠️ Autant de cas qui doivent ÉCHOUER que de cas qui passent (règle #28).
 */
describe('CreatePromoDto — validation d’entrée', () => {
  const valide = {
    description: 'Sardines fraîches du jour',
    prixAvant: 1000,
    prixApres: 700,
    categorie: 'alimentation',
    photoKeys: ['promo-photos/abc/def.jpg'],
  };

  const erreursDe = (patch: Record<string, unknown>): string[] => {
    const dto = plainToInstance(CreatePromoDto, { ...valide, ...patch });
    return validateSync(dto).map((e) => e.property);
  };

  // ── Doivent PASSER ────────────────────────────────────────────────────────

  it('accepte une promo nominale', () => {
    expect(erreursDe({})).toEqual([]);
  });

  it('accepte un prix exactement au plafond de la colonne', () => {
    expect(erreursDe({ prixAvant: PRIX_MAX, prixApres: 1 })).toEqual([]);
  });

  it('accepte une durée en jours', () => {
    expect(erreursDe({ dureeJours: 7 })).toEqual([]);
  });

  it('accepte 3 photos, le maximum', () => {
    expect(erreursDe({ photoKeys: ['a', 'b', 'c'] })).toEqual([]);
  });

  // ── Doivent REFUSER ───────────────────────────────────────────────────────

  it('refuse un prix au-delà de numeric(10,2) — sinon Postgres lève un 500', () => {
    expect(erreursDe({ prixAvant: PRIX_MAX + 1 })).toContain('prixAvant');
    expect(erreursDe({ prixApres: 1e12 })).toContain('prixApres');
  });

  it('refuse un prix négatif ou nul', () => {
    expect(erreursDe({ prixAvant: 0 })).toContain('prixAvant');
    expect(erreursDe({ prixApres: -5 })).toContain('prixApres');
  });

  it('refuse un prix envoyé comme chaîne', () => {
    expect(erreursDe({ prixAvant: '1000' })).toContain('prixAvant');
  });

  it('refuse une description hors bornes', () => {
    expect(erreursDe({ description: 'x' })).toContain('description');
    expect(erreursDe({ description: 'x'.repeat(141) })).toContain(
      'description',
    );
  });

  it('refuse une catégorie inconnue', () => {
    expect(erreursDe({ categorie: 'nimporte-quoi' })).toContain('categorie');
  });

  it('refuse 0 ou 4 photos, et une clé vide', () => {
    expect(erreursDe({ photoKeys: [] })).toContain('photoKeys');
    expect(erreursDe({ photoKeys: ['a', 'b', 'c', 'd'] })).toContain(
      'photoKeys',
    );
    expect(erreursDe({ photoKeys: [''] })).toContain('photoKeys');
  });

  it('refuse une durée négative', () => {
    expect(erreursDe({ dureeJours: -1 })).toContain('dureeJours');
  });

  it('refuse une date de fin qui n’en est pas une', () => {
    expect(erreursDe({ dateFin: 'pas-une-date' })).toContain('dateFin');
  });
});

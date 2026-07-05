import { plainToInstance } from 'class-transformer';
import { validateSync } from 'class-validator';
import { PaginationQueryDto } from './pagination-query.dto';

function parse(query: Record<string, string>): PaginationQueryDto {
  return plainToInstance(PaginationQueryDto, query, {
    enableImplicitConversion: false,
  });
}

describe('PaginationQueryDto', () => {
  it('retombe sur page=1/limit=20 par défaut si absents', () => {
    const dto = parse({});
    expect(validateSync(dto)).toHaveLength(0);
    expect(dto.page).toBe(1);
    expect(dto.limit).toBe(20);
  });

  it('accepte page/limit valides fournis en query string', () => {
    const dto = parse({ page: '3', limit: '50' });
    expect(validateSync(dto)).toHaveLength(0);
    expect(dto.page).toBe(3);
    expect(dto.limit).toBe(50);
  });

  it('rejette une limit au-delà de MAX_PAGE_SIZE (100)', () => {
    const dto = parse({ limit: '500' });
    expect(validateSync(dto).length).toBeGreaterThan(0);
  });

  it('rejette une page négative ou nulle', () => {
    const dto = parse({ page: '0' });
    expect(validateSync(dto).length).toBeGreaterThan(0);
  });
});

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  limit: number;
}

export function toPaginatedResult<T>(
  items: T[],
  total: number,
  page: number,
  limit: number,
): PaginatedResult<T> {
  return { items, total, page, limit };
}

export type Role = 'commercant' | 'agent' | 'admin';

export interface AuthTokenPayload {
  sub: string;
  role: Role;
  /** Présent uniquement pour agent/admin (rôles à droits d'écriture larges) — permet la révocation. */
  tokenVersion?: number;
}

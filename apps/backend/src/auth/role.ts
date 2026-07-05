export type Role = 'commercant' | 'agent' | 'admin';

export interface AuthTokenPayload {
  sub: string;
  role: Role;
  /** Permet la révocation (JwtAuthGuard compare à la valeur en base à chaque requête). */
  tokenVersion: number;
}

export type Role = 'commercant' | 'agent' | 'admin';

export interface AuthTokenPayload {
  sub: string;
  role: Role;
}

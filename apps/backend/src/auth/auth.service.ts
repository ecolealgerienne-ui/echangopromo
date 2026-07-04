import { Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { AuthTokenPayload, Role } from './role';

const SALT_ROUNDS = 10;

@Injectable()
export class AuthService {
  constructor(private readonly jwtService: JwtService) {}

  async hash(value: string): Promise<string> {
    return bcrypt.hash(value, SALT_ROUNDS);
  }

  async compare(value: string, hash: string): Promise<boolean> {
    return bcrypt.compare(value, hash);
  }

  issueToken(sub: string, role: Role): string {
    const payload: AuthTokenPayload = { sub, role };
    return this.jwtService.sign(payload);
  }
}

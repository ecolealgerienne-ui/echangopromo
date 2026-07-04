import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Request } from 'express';
import { Repository } from 'typeorm';
import { Admin } from '../../admin/entities/admin.entity';
import { Agent } from '../../agent/entities/agent.entity';
import type { AuthTokenPayload } from '../role';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    // Accès direct aux entités agent/admin (hors de leurs modules respectifs)
    // pour éviter un cycle AuthModule ↔ AgentModule/AdminModule — cf. CLAUDE.md
    // règle #9. Sert uniquement à vérifier le tokenVersion (révocation, règle #6).
    @InjectRepository(Agent) private readonly agents: Repository<Agent>,
    @InjectRepository(Admin) private readonly admins: Repository<Admin>,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractToken(request);
    if (!token) {
      throw new UnauthorizedException('Token manquant');
    }

    let payload: AuthTokenPayload;
    try {
      payload = this.jwtService.verify<AuthTokenPayload>(token);
    } catch {
      throw new UnauthorizedException('Token invalide ou expiré');
    }

    if (payload.role === 'agent' || payload.role === 'admin') {
      const repo = payload.role === 'agent' ? this.agents : this.admins;
      const account = await repo.findOne({ where: { id: payload.sub } });
      if (!account || account.tokenVersion !== payload.tokenVersion) {
        throw new UnauthorizedException('Token révoqué');
      }
    }

    (request as Request & { user: AuthTokenPayload }).user = payload;
    return true;
  }

  private extractToken(request: Request): string | null {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) return null;
    return header.slice('Bearer '.length);
  }
}

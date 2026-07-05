import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Request } from 'express';
import { Repository } from 'typeorm';
import { Admin } from '../../admin/entities/admin.entity';
import { Agent } from '../../agent/entities/agent.entity';
import { UnauthorizedAppException } from '../../common/errors/app-exception';
import { ErrorCode } from '../../common/errors/error-code.enum';
import { Commercant } from '../../commercant/entities/commercant.entity';
import type { AuthTokenPayload, Role } from '../role';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtService: JwtService,
    // Accès direct aux entités agent/admin/commercant (hors de leurs modules
    // respectifs) pour éviter un cycle AuthModule ↔ Agent/Admin/CommercantModule
    // — cf. CLAUDE.md règle #9. Sert uniquement à vérifier le tokenVersion
    // (révocation, règle #6).
    @InjectRepository(Agent) private readonly agents: Repository<Agent>,
    @InjectRepository(Admin) private readonly admins: Repository<Admin>,
    @InjectRepository(Commercant) private readonly commercants: Repository<Commercant>,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractToken(request);
    if (!token) {
      throw new UnauthorizedAppException(ErrorCode.AUTH_TOKEN_MISSING, 'Token manquant');
    }

    let payload: AuthTokenPayload;
    try {
      payload = this.jwtService.verify<AuthTokenPayload>(token);
    } catch {
      throw new UnauthorizedAppException(ErrorCode.AUTH_TOKEN_INVALID, 'Token invalide ou expiré');
    }

    const repo = this.repositoryFor(payload.role);
    const account = await repo.findOne({ where: { id: payload.sub } });
    if (!account || account.tokenVersion !== payload.tokenVersion) {
      throw new UnauthorizedAppException(ErrorCode.AUTH_TOKEN_REVOKED, 'Token révoqué');
    }

    (request as Request & { user: AuthTokenPayload }).user = payload;
    return true;
  }

  private repositoryFor(
    role: Role,
  ): Repository<Agent> | Repository<Admin> | Repository<Commercant> {
    switch (role) {
      case 'agent':
        return this.agents;
      case 'admin':
        return this.admins;
      case 'commercant':
        return this.commercants;
    }
  }

  private extractToken(request: Request): string | null {
    const header = request.headers.authorization;
    if (!header?.startsWith('Bearer ')) return null;
    return header.slice('Bearer '.length);
  }
}

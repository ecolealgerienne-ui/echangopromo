import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { ForbiddenAppException } from '../../common/errors/app-exception';
import { ErrorCode } from '../../common/errors/error-code.enum';
import { ROLES_KEY } from '../decorators/roles.decorator';
import type { AuthTokenPayload, Role } from '../role';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[] | undefined>(
      ROLES_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (!requiredRoles || requiredRoles.length === 0) return true;

    const request = context
      .switchToHttp()
      .getRequest<Request & { user?: AuthTokenPayload }>();
    if (!request.user || !requiredRoles.includes(request.user.role)) {
      throw new ForbiddenAppException(ErrorCode.AUTH_FORBIDDEN_ROLE, 'Accès refusé pour ce rôle');
    }
    return true;
  }
}

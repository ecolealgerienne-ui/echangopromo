import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';
import type { AuthTokenPayload } from '../role';

export const CurrentUser = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthTokenPayload => {
    const request = ctx
      .switchToHttp()
      .getRequest<Request & { user: AuthTokenPayload }>();
    return request.user;
  },
);

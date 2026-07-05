import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';
import { BadRequestAppException } from '../errors/app-exception';
import { ErrorCode } from '../errors/error-code.enum';

/**
 * Identifiant device anonyme envoyé par l'app client (specs §3.1/§5.4) —
 * jamais un compte, uniquement utilisé pour dédupliquer vues/signalements.
 */
export const DeviceId = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): string => {
    const request = ctx.switchToHttp().getRequest<Request>();
    const deviceId = request.headers['x-device-id'];
    if (typeof deviceId !== 'string' || deviceId.trim().length === 0) {
      throw new BadRequestAppException(
        ErrorCode.DEVICE_ID_MISSING,
        'En-tête X-Device-Id manquant',
      );
    }
    return deviceId;
  },
);

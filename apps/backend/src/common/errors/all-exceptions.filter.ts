import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Response } from 'express';
import { ErrorCode } from './error-code.enum';

/**
 * Garantit que toute réponse d'erreur a la forme {statusCode, code, message},
 * y compris pour les exceptions qui ne portent pas de `code` par construction
 * (ValidationPipe, ThrottlerException, erreur non prévue) — le mobile n'a
 * qu'un seul format à parser (voir ApiException côté mobile).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const response = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse();

      if (typeof body === 'object' && body !== null && 'code' in body) {
        response.status(status).json(body);
        return;
      }

      const message =
        typeof body === 'object' && body !== null && 'message' in body
          ? (body as { message: string | string[] }).message
          : exception.message;

      response.status(status).json({
        statusCode: status,
        code: this.fallbackCode(status),
        message,
      });
      return;
    }

    this.logger.error(exception);
    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      code: ErrorCode.INTERNAL_ERROR,
      message: 'Une erreur inattendue est survenue.',
    });
  }

  private fallbackCode(status: HttpStatus): ErrorCode {
    switch (status) {
      case HttpStatus.BAD_REQUEST:
        return ErrorCode.VALIDATION_ERROR;
      case HttpStatus.TOO_MANY_REQUESTS:
        return ErrorCode.RATE_LIMITED;
      // Le seul 413 du produit vient de la limite Multer de
      // `StorageController.upload` : le fichier n'atteint jamais
      // `StorageService.uploadPhoto`, donc jamais le refus métier
      // `STORAGE_FILE_TOO_LARGE` — il tombait dans `HTTP_ERROR` alors que ce
      // code existe et est traduit dans les trois langues. Le mobile
      // affichait « une erreur est survenue » sur une cause parfaitement
      // nommable et corrigeable par l'utilisateur (revue 2026-08-05).
      case HttpStatus.PAYLOAD_TOO_LARGE:
        return ErrorCode.STORAGE_FILE_TOO_LARGE;
      default:
        return ErrorCode.HTTP_ERROR;
    }
  }
}

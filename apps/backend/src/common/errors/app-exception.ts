import { HttpException, HttpStatus } from '@nestjs/common';
import { ErrorCode } from './error-code.enum';

/**
 * Exception HTTP portant un `code` stable en plus du `message` — voir
 * error-code.enum.ts. Les sous-classes ci-dessous ne font que fixer le
 * status HTTP pour éviter de le répéter à chaque site d'appel.
 */
export class AppException extends HttpException {
  constructor(status: HttpStatus, code: ErrorCode, message: string) {
    super({ statusCode: status, code, message }, status);
  }
}

export class BadRequestAppException extends AppException {
  constructor(code: ErrorCode, message: string) {
    super(HttpStatus.BAD_REQUEST, code, message);
  }
}

export class NotFoundAppException extends AppException {
  constructor(code: ErrorCode, message: string) {
    super(HttpStatus.NOT_FOUND, code, message);
  }
}

export class UnauthorizedAppException extends AppException {
  constructor(code: ErrorCode, message: string) {
    super(HttpStatus.UNAUTHORIZED, code, message);
  }
}

export class ForbiddenAppException extends AppException {
  constructor(code: ErrorCode, message: string) {
    super(HttpStatus.FORBIDDEN, code, message);
  }
}

export class ConflictAppException extends AppException {
  constructor(code: ErrorCode, message: string) {
    super(HttpStatus.CONFLICT, code, message);
  }
}

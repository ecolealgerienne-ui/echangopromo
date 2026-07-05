import { ExecutionContext, HttpException } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

type Repo = { findOne: jest.Mock };

function makeContext(authHeader?: string): ExecutionContext {
  const request = { headers: { authorization: authHeader } };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

async function errorCode(promise: Promise<unknown>): Promise<string | undefined> {
  try {
    await promise;
    return undefined;
  } catch (error) {
    const response = (error as HttpException).getResponse();
    return typeof response === 'object' && response !== null
      ? (response as { code?: string }).code
      : undefined;
  }
}

describe('JwtAuthGuard', () => {
  let jwtService: { verify: jest.Mock };
  let agents: Repo;
  let admins: Repo;
  let commercants: Repo;
  let guard: JwtAuthGuard;

  beforeEach(() => {
    jwtService = { verify: jest.fn() };
    agents = { findOne: jest.fn() };
    admins = { findOne: jest.fn() };
    commercants = { findOne: jest.fn() };
    guard = new JwtAuthGuard(
      jwtService as never,
      agents as never,
      admins as never,
      commercants as never,
    );
  });

  it('rejette une requête sans en-tête Authorization (AUTH_TOKEN_MISSING)', async () => {
    expect(await errorCode(guard.canActivate(makeContext(undefined)))).toBe(
      'AUTH_TOKEN_MISSING',
    );
  });

  it('rejette un token que jwtService ne parvient pas à vérifier (AUTH_TOKEN_INVALID)', async () => {
    jwtService.verify.mockImplementation(() => {
      throw new Error('expired');
    });
    expect(await errorCode(guard.canActivate(makeContext('Bearer abc')))).toBe(
      'AUTH_TOKEN_INVALID',
    );
  });

  it('rejette un token dont le tokenVersion ne correspond plus au compte (AUTH_TOKEN_REVOKED)', async () => {
    jwtService.verify.mockReturnValue({ sub: 'agent-1', role: 'agent', tokenVersion: 0 });
    agents.findOne.mockResolvedValue({ id: 'agent-1', tokenVersion: 1 });
    expect(await errorCode(guard.canActivate(makeContext('Bearer abc')))).toBe(
      'AUTH_TOKEN_REVOKED',
    );
  });

  it("rejette si le compte n'existe plus", async () => {
    jwtService.verify.mockReturnValue({
      sub: 'commercant-1',
      role: 'commercant',
      tokenVersion: 0,
    });
    commercants.findOne.mockResolvedValue(null);
    expect(await errorCode(guard.canActivate(makeContext('Bearer abc')))).toBe(
      'AUTH_TOKEN_REVOKED',
    );
  });

  it('accepte un token valide dont le tokenVersion correspond', async () => {
    jwtService.verify.mockReturnValue({ sub: 'admin-1', role: 'admin', tokenVersion: 2 });
    admins.findOne.mockResolvedValue({ id: 'admin-1', tokenVersion: 2 });
    await expect(guard.canActivate(makeContext('Bearer abc'))).resolves.toBe(true);
  });
});

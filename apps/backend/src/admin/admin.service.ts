import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { Admin } from './entities/admin.entity';

@Injectable()
export class AdminService {
  constructor(
    @InjectRepository(Admin) private readonly admins: Repository<Admin>,
    private readonly authService: AuthService,
  ) {}

  async login(email: string, password: string): Promise<Admin> {
    const admin = await this.admins.findOne({ where: { email } });
    if (!admin) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }
    const matches = await this.authService.compare(
      password,
      admin.passwordHash,
    );
    if (!matches) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }
    return admin;
  }

  async findByIdOrFail(id: string): Promise<Admin> {
    const admin = await this.admins.findOne({ where: { id } });
    if (!admin) {
      throw new NotFoundAppException(ErrorCode.ADMIN_NOT_FOUND, 'Admin introuvable');
    }
    return admin;
  }

  /** Révoque tous les JWT déjà émis pour ce compte (device perdu/volé) — même levier que pour un agent. */
  async revokeOwnTokens(adminId: string): Promise<void> {
    await this.admins.increment({ id: adminId }, 'tokenVersion', 1);
  }
}

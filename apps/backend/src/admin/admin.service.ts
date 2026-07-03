import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
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
      throw new BadRequestException('Identifiants invalides');
    }
    const matches = await this.authService.compare(
      password,
      admin.passwordHash,
    );
    if (!matches) {
      throw new BadRequestException('Identifiants invalides');
    }
    return admin;
  }

  async findByIdOrFail(id: string): Promise<Admin> {
    const admin = await this.admins.findOne({ where: { id } });
    if (!admin) {
      throw new NotFoundException('Admin introuvable');
    }
    return admin;
  }
}

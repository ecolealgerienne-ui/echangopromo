import { BadRequestException, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { randomInt } from 'crypto';
import { IsNull, Repository } from 'typeorm';
import { OtpCode, OtpPurpose } from './entities/otp-code.entity';
import { AuthTokenPayload, Role } from './role';
import { SmsService } from './sms.service';

const OTP_LENGTH = 6;
const OTP_TTL_MINUTES = 5;
const SALT_ROUNDS = 10;

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(OtpCode)
    private readonly otpRepository: Repository<OtpCode>,
    private readonly jwtService: JwtService,
    private readonly smsService: SmsService,
  ) {}

  async hash(value: string): Promise<string> {
    return bcrypt.hash(value, SALT_ROUNDS);
  }

  async compare(value: string, hash: string): Promise<boolean> {
    return bcrypt.compare(value, hash);
  }

  issueToken(sub: string, role: Role): string {
    const payload: AuthTokenPayload = { sub, role };
    return this.jwtService.sign(payload);
  }

  async sendOtp(telephone: string, purpose: OtpPurpose): Promise<void> {
    const code = randomInt(0, 10 ** OTP_LENGTH)
      .toString()
      .padStart(OTP_LENGTH, '0');
    const codeHash = await this.hash(code);
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000);

    await this.otpRepository.save(
      this.otpRepository.create({ telephone, codeHash, purpose, expiresAt }),
    );

    await this.smsService.send(
      telephone,
      `echango Promo — votre code de vérification : ${code} (valable ${OTP_TTL_MINUTES} min)`,
    );
  }

  async verifyOtp(
    telephone: string,
    purpose: OtpPurpose,
    code: string,
  ): Promise<void> {
    const candidate = await this.otpRepository.findOne({
      where: { telephone, purpose, consumedAt: IsNull() },
      order: { createdAt: 'DESC' },
    });

    if (!candidate || candidate.expiresAt < new Date()) {
      throw new BadRequestException('Code invalide ou expiré');
    }

    const matches = await this.compare(code, candidate.codeHash);
    if (!matches) {
      throw new BadRequestException('Code invalide ou expiré');
    }

    candidate.consumedAt = new Date();
    await this.otpRepository.save(candidate);
  }
}

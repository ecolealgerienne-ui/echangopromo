import { BadRequestException, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcryptjs';
import { randomInt } from 'crypto';
import { IsNull, MoreThan, Repository } from 'typeorm';
import { OtpCode, OtpPurpose } from './entities/otp-code.entity';
import { AuthTokenPayload, Role } from './role';
import { SmsService } from './sms.service';

const OTP_LENGTH = 6;
const OTP_TTL_MINUTES = 5;
const OTP_RESEND_COOLDOWN_SECONDS = 60;
const OTP_MAX_ATTEMPTS = 5;
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

  /**
   * Cooldown d'envoi indépendant de l'expiration du code (specs audit
   * sécurité) : sans ça, `sendOtp` est appelable en boucle et permet de
   * spammer un numéro tiers en SMS.
   */
  async sendOtp(telephone: string, purpose: OtpPurpose): Promise<void> {
    const cooldownStart = new Date(
      Date.now() - OTP_RESEND_COOLDOWN_SECONDS * 1000,
    );
    const recent = await this.otpRepository.findOne({
      where: { telephone, purpose, createdAt: MoreThan(cooldownStart) },
      order: { createdAt: 'DESC' },
    });
    if (recent) {
      throw new BadRequestException(
        `Veuillez attendre ${OTP_RESEND_COOLDOWN_SECONDS} secondes avant de redemander un code`,
      );
    }

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

  /**
   * Compteur de tentatives indépendant de l'expiration (specs audit
   * sécurité) : sans ça, un code à 6 chiffres est brute-forçable en ligne
   * pendant toute sa fenêtre de validité de 5 minutes.
   */
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

    if (candidate.attempts >= OTP_MAX_ATTEMPTS) {
      throw new BadRequestException(
        'Trop de tentatives — demandez un nouveau code',
      );
    }

    const matches = await this.compare(code, candidate.codeHash);
    if (!matches) {
      candidate.attempts += 1;
      await this.otpRepository.save(candidate);
      throw new BadRequestException('Code invalide ou expiré');
    }

    candidate.consumedAt = new Date();
    await this.otpRepository.save(candidate);
  }
}

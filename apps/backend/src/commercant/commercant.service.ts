import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { OtpPurpose } from '../auth/entities/otp-code.entity';
import { AuthService } from '../auth/auth.service';
import { Promo, PromoStatus } from '../promo/entities/promo.entity';
import { CommercantView } from './entities/commercant-view.entity';
import {
  Commercant,
  CommercantAccountState,
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';
import { ConfirmPhoneDto } from './dto/confirm-phone.dto';
import { CreateCommercantByAgentDto } from './dto/create-commercant-by-agent.dto';
import { RegisterCommercantDto } from './dto/register-commercant.dto';

export type ZoneCommerceStatus = 'jamais_visite' | 'a_jour' | 'a_relancer';

@Injectable()
export class CommercantService {
  constructor(
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    @InjectRepository(CommercantView)
    private readonly views: Repository<CommercantView>,
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
    private readonly authService: AuthService,
  ) {}

  private async assertPhoneAvailable(telephone: string): Promise<void> {
    const existing = await this.commercants.findOne({ where: { telephone } });
    if (existing) {
      throw new ConflictException('Ce numéro de téléphone est déjà enregistré');
    }
  }

  /** Auto-inscription (specs §3.2, voie 1) — pas de passage agent requis. */
  async selfRegister(dto: RegisterCommercantDto): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);

    const commercant = await this.commercants.save(
      this.commercants.create({
        ...dto,
        accountState: CommercantAccountState.EN_ATTENTE_REVENDICATION,
        originVerification: CommercantOriginVerification.AUTO_INSCRIT,
      }),
    );

    await this.authService.sendOtp(dto.telephone, OtpPurpose.INSCRIPTION);
    return commercant;
  }

  /** Création assistée par l'agent (specs §3.2, voie 2) — pas d'OTP envoyé ici. */
  async createByAgent(
    dto: CreateCommercantByAgentDto,
    agentId: string,
    zoneId: string | null,
  ): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);

    return this.commercants.save(
      this.commercants.create({
        ...dto,
        zoneId,
        createdByAgentId: agentId,
        accountState: CommercantAccountState.CREE_AGENT,
        originVerification: CommercantOriginVerification.CONFIRME_AGENT,
      }),
    );
  }

  /** L'agent initie la revendication : déclenche l'envoi de l'OTP (specs §3.3). */
  async initiateClaim(commercantId: string): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (commercant.accountState !== CommercantAccountState.CREE_AGENT) {
      throw new BadRequestException(
        'La revendication a déjà été initiée pour ce commerçant',
      );
    }

    commercant.accountState = CommercantAccountState.EN_ATTENTE_REVENDICATION;
    await this.commercants.save(commercant);
    await this.authService.sendOtp(
      commercant.telephone,
      OtpPurpose.REVENDICATION,
    );
  }

  /**
   * Valide l'OTP (inscription ou revendication) et définit le PIN. Les deux
   * voies convergent directement vers `autonome` : le spec ne définit aucune
   * règle métier distinguant `revendique` d'`autonome`, donc on saute
   * l'état intermédiaire plutôt que d'introduire une distinction arbitraire.
   */
  async confirmPhoneAndSetPin(
    purpose: OtpPurpose,
    dto: ConfirmPhoneDto,
  ): Promise<Commercant> {
    const commercant = await this.commercants.findOne({
      where: { telephone: dto.telephone },
    });
    if (!commercant) {
      throw new NotFoundException('Commerçant introuvable');
    }

    await this.authService.verifyOtp(dto.telephone, purpose, dto.code);

    commercant.pinHash = await this.authService.hash(dto.pin);
    commercant.telephoneVerifiedAt = new Date();
    commercant.accountState = CommercantAccountState.AUTONOME;
    return this.commercants.save(commercant);
  }

  async login(telephone: string, pin: string): Promise<Commercant> {
    const commercant = await this.commercants.findOne({ where: { telephone } });
    if (!commercant?.pinHash) {
      throw new BadRequestException('Identifiants invalides');
    }

    const matches = await this.authService.compare(pin, commercant.pinHash);
    if (!matches) {
      throw new BadRequestException('Identifiants invalides');
    }

    return commercant;
  }

  async requestForgotPin(telephone: string): Promise<void> {
    const commercant = await this.commercants.findOne({ where: { telephone } });
    if (!commercant?.pinHash) {
      throw new NotFoundException('Commerçant introuvable');
    }
    await this.authService.sendOtp(telephone, OtpPurpose.PIN_OUBLIE);
  }

  async confirmForgotPin(
    telephone: string,
    code: string,
    newPin: string,
  ): Promise<void> {
    const commercant = await this.commercants.findOne({ where: { telephone } });
    if (!commercant) {
      throw new NotFoundException('Commerçant introuvable');
    }

    await this.authService.verifyOtp(telephone, OtpPurpose.PIN_OUBLIE, code);
    commercant.pinHash = await this.authService.hash(newPin);
    await this.commercants.save(commercant);
  }

  async findByIdOrFail(id: string): Promise<Commercant> {
    const commercant = await this.commercants.findOne({ where: { id } });
    if (!commercant) {
      throw new NotFoundException('Commerçant introuvable');
    }
    return commercant;
  }

  async findPublicProfile(id: string): Promise<Commercant> {
    return this.findByIdOrFail(id);
  }

  async requestRegistreVerification(
    commercantId: string,
    registreKey: string,
  ): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.registreKey = registreKey;
    commercant.registreStatus = RegistreStatus.EN_ATTENTE;
    await this.commercants.save(commercant);
  }

  /** Décision admin sur le badge `vérifié_registre` — jamais bloquant pour publier (specs §3.2). */
  async resolveRegistreVerification(
    commercantId: string,
    approve: boolean,
  ): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (commercant.registreStatus !== RegistreStatus.EN_ATTENTE) {
      throw new BadRequestException(
        'Aucune demande de vérification en attente',
      );
    }

    commercant.registreStatus = approve
      ? RegistreStatus.VALIDE
      : RegistreStatus.REJETE;
    commercant.registreValidatedAt = approve ? new Date() : null;
    await this.commercants.save(commercant);
  }

  async recordProfileView(
    commercantId: string,
    deviceId: string,
  ): Promise<void> {
    await this.views
      .createQueryBuilder()
      .insert()
      .values({ commercantId, deviceId })
      .orIgnore()
      .execute();
  }

  async getDashboardStats(
    commercantId: string,
  ): Promise<{ profileViewCount: number }> {
    const profileViewCount = await this.views.count({
      where: { commercantId },
    });
    return { profileViewCount };
  }

  /**
   * Commerces d'une zone avec statut de tournée (specs §3.3). Faute d'un
   * horodatage explicite de "dernière visite" dans les specs, le statut est
   * dérivé de l'état des promos : jamais publié / a une promo active / n'a
   * plus que des promos expirées.
   */
  async listByZoneWithVisitStatus(
    zoneId: string,
  ): Promise<Array<Commercant & { visitStatus: ZoneCommerceStatus }>> {
    const commercants = await this.commercants.find({ where: { zoneId } });

    const results = await Promise.all(
      commercants.map(async (commercant) => {
        const totalPromos = await this.promos.count({
          where: { commercantId: commercant.id },
        });
        const activePromos = await this.promos.count({
          where: { commercantId: commercant.id, status: PromoStatus.ACTIVE },
        });

        let visitStatus: ZoneCommerceStatus;
        if (totalPromos === 0) visitStatus = 'jamais_visite';
        else if (activePromos > 0) visitStatus = 'a_jour';
        else visitStatus = 'a_relancer';

        return Object.assign(commercant, { visitStatus });
      }),
    );

    return results;
  }

  async countActive(): Promise<number> {
    return this.commercants.count({
      where: { accountState: CommercantAccountState.AUTONOME },
    });
  }
}

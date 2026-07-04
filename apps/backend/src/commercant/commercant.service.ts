import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import { Promo, VISIBLE_PROMO_STATUSES } from '../promo/entities/promo.entity';
import { CommercantView } from './entities/commercant-view.entity';
import {
  Commercant,
  CommercantAccountState,
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';
import { ClaimCommercantDto } from './dto/claim-commercant.dto';
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

  /**
   * Auto-inscription (specs §3.2, voie 1) — pas de passage agent requis, et
   * pas d'OTP (décision produit) : le compte est `autonome` dès la saisie du
   * PIN, sans preuve de possession du numéro de téléphone.
   */
  async selfRegister(dto: RegisterCommercantDto): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);

    const { pin, ...rest } = dto;
    return this.commercants.save(
      this.commercants.create({
        ...rest,
        telephone: dto.telephone,
        pinHash: await this.authService.hash(pin),
        accountState: CommercantAccountState.AUTONOME,
        originVerification: CommercantOriginVerification.AUTO_INSCRIT,
      }),
    );
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

  /**
   * Le commerçant définit lui-même son PIN pour activer un compte créé par
   * un agent, ou pour se réactiver après une réinitialisation par l'admin
   * (§3.3) — aucun OTP : seul le numéro de téléphone est requis (décision
   * produit assumée, voir §3.2 des specs). Refusé si un PIN est déjà défini,
   * pour ne pas permettre l'écrasement silencieux du PIN d'un tiers.
   */
  async claim(dto: ClaimCommercantDto): Promise<Commercant> {
    const commercant = await this.commercants.findOne({
      where: { telephone: dto.telephone },
    });
    if (!commercant) {
      throw new NotFoundException('Commerçant introuvable');
    }
    if (commercant.pinHash) {
      throw new ConflictException(
        'Un PIN est déjà défini pour ce numéro — contactez un administrateur pour le réinitialiser',
      );
    }

    commercant.pinHash = await this.authService.hash(dto.pin);
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

  /**
   * PIN oublié : pas de flux libre-service (pas d'OTP pour reprouver la
   * possession du numéro). Seul l'admin peut effacer le PIN ; le commerçant
   * en définit ensuite un nouveau via `claim`, exactement comme pour un
   * compte créé par un agent.
   */
  async adminResetPin(commercantId: string): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.pinHash = null;
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
   * dérivé de l'état des promos : jamais publié / a une promo visible / n'a
   * plus que des promos expirées ou masquées.
   *
   * Deux requêtes agrégées (pas une par commerçant) : le statut "à jour"
   * doit utiliser la même définition de "promo visible" que le client
   * (`VISIBLE_PROMO_STATUSES`), pas seulement `ACTIVE` — sinon une promo
   * `verifiee_ok` fait apparaître à tort le commerçant comme "à relancer".
   */
  async listByZoneWithVisitStatus(
    zoneId: string,
  ): Promise<Array<Commercant & { visitStatus: ZoneCommerceStatus }>> {
    const commercants = await this.commercants.find({ where: { zoneId } });
    if (commercants.length === 0) return [];

    const commercantIds = commercants.map((c) => c.id);

    const totalRows = await this.promos
      .createQueryBuilder('promo')
      .select('promo.commercantId', 'commercantId')
      .addSelect('COUNT(*)', 'count')
      .where('promo.commercantId IN (:...commercantIds)', { commercantIds })
      .groupBy('promo.commercantId')
      .getRawMany<{ commercantId: string; count: string }>();

    const visibleRows = await this.promos
      .createQueryBuilder('promo')
      .select('promo.commercantId', 'commercantId')
      .addSelect('COUNT(*)', 'count')
      .where('promo.commercantId IN (:...commercantIds)', { commercantIds })
      .andWhere('promo.status IN (:...visibleStatuses)', {
        visibleStatuses: VISIBLE_PROMO_STATUSES,
      })
      .groupBy('promo.commercantId')
      .getRawMany<{ commercantId: string; count: string }>();

    const totalByCommercant = new Map(
      totalRows.map((row) => [row.commercantId, Number(row.count)]),
    );
    const visibleByCommercant = new Map(
      visibleRows.map((row) => [row.commercantId, Number(row.count)]),
    );

    return commercants.map((commercant) => {
      const total = totalByCommercant.get(commercant.id) ?? 0;
      const visible = visibleByCommercant.get(commercant.id) ?? 0;

      let visitStatus: ZoneCommerceStatus;
      if (total === 0) visitStatus = 'jamais_visite';
      else if (visible > 0) visitStatus = 'a_jour';
      else visitStatus = 'a_relancer';

      return Object.assign(commercant, { visitStatus });
    });
  }

  async countActive(): Promise<number> {
    return this.commercants.count({
      where: { accountState: CommercantAccountState.AUTONOME },
    });
  }

  /** Garde IDOR : un agent ne peut agir que sur les commerçants de sa propre zone. */
  async assertZoneMatches(
    commercantId: string,
    agentZoneId: string | null,
  ): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (!agentZoneId || commercant.zoneId !== agentZoneId) {
      throw new ForbiddenException(
        "Ce commerçant n'est pas dans la zone de cet agent",
      );
    }
    return commercant;
  }
}

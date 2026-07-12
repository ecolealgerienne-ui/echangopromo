import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import {
  BadRequestAppException,
  ConflictAppException,
  ForbiddenAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import {
  NotificationRecipientType,
  NotificationType,
} from '../notification/entities/notification.entity';
import { NotificationService } from '../notification/notification.service';
import {
  Promo,
  PromoLifecycleStatus,
  VISIBLE_MODERATION_STATUSES,
} from '../promo/entities/promo.entity';
import { StorageService } from '../storage/storage.service';
import { CommercantView } from './entities/commercant-view.entity';
import {
  Commercant,
  CommercantAccountState,
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';
import { ClaimCommercantDto } from './dto/claim-commercant.dto';
import { CreateCommercantByAgentDto } from './dto/create-commercant-by-agent.dto';
import { ListCommercantQueryDto } from './dto/list-commercant-query.dto';
import { RegisterCommercantDto } from './dto/register-commercant.dto';
import { UpdateCommercantDto } from './dto/update-commercant.dto';

export type CommuneCommerceStatus = 'jamais_visite' | 'a_jour' | 'a_relancer';

@Injectable()
export class CommercantService {
  constructor(
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    @InjectRepository(CommercantView)
    private readonly views: Repository<CommercantView>,
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
    private readonly authService: AuthService,
    private readonly storageService: StorageService,
    private readonly notificationService: NotificationService,
  ) {}

  private async assertPhoneAvailable(telephone: string): Promise<void> {
    const existing = await this.commercants.findOne({ where: { telephone } });
    if (existing) {
      throw new ConflictAppException(
        ErrorCode.COMMERCANT_PHONE_TAKEN,
        'Ce numéro de téléphone est déjà enregistré',
      );
    }
  }

  /**
   * Auto-inscription (specs §3.2, voie 1) — pas de passage agent requis, et
   * pas d'OTP (décision produit) : le compte est `autonome` dès la saisie du
   * PIN, sans preuve de possession du numéro de téléphone. `acceptedTerms`
   * vérifié explicitement (pas juste sa présence) : spec §7.4, CGU à traiter
   * avant toute ouverture publique — plan de correction Phase 4.
   */
  async selfRegister(dto: RegisterCommercantDto): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);
    if (dto.acceptedTerms !== true) {
      throw new BadRequestAppException(
        ErrorCode.COMMERCANT_TERMS_NOT_ACCEPTED,
        "Vous devez accepter les conditions d'utilisation pour créer un compte",
      );
    }

    const { pin, ...rest } = dto;
    return this.commercants.save(
      this.commercants.create({
        ...rest,
        telephone: dto.telephone,
        pinHash: await this.authService.hash(pin),
        accountState: CommercantAccountState.AUTONOME,
        originVerification: CommercantOriginVerification.AUTO_INSCRIT,
        consentedAt: new Date(),
      }),
    );
  }

  /** Création assistée par l'agent (specs §3.2, voie 2) — pas d'OTP envoyé ici. */
  async createByAgent(
    dto: CreateCommercantByAgentDto,
    agentId: string,
  ): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);

    return this.commercants.save(
      this.commercants.create({
        ...dto,
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
      throw new NotFoundAppException(ErrorCode.COMMERCANT_NOT_FOUND, 'Commerçant introuvable');
    }
    if (commercant.pinHash) {
      throw new ConflictAppException(
        ErrorCode.COMMERCANT_PIN_ALREADY_SET,
        'Un PIN est déjà défini pour ce numéro — contactez un administrateur pour le réinitialiser',
      );
    }

    commercant.pinHash = await this.authService.hash(dto.pin);
    commercant.accountState = CommercantAccountState.AUTONOME;
    return this.commercants.save(commercant);
  }

  async login(telephone: string, pin: string): Promise<Commercant> {
    const commercant = await this.commercants.findOne({ where: { telephone } });
    // Un compte supprimé (soft delete) est traité comme des identifiants
    // invalides plutôt qu'un message dédié — évite de confirmer à un tiers
    // que ce numéro a un jour eu un compte.
    if (!commercant?.pinHash || commercant.deletedAt) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }

    const matches = await this.authService.compare(pin, commercant.pinHash);
    if (!matches) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }

    return commercant;
  }

  /**
   * PIN oublié : pas de flux libre-service (pas d'OTP pour reprouver la
   * possession du numéro). Seul l'admin peut effacer le PIN ; le commerçant
   * en définit ensuite un nouveau via `claim`, exactement comme pour un
   * compte créé par un agent. Incrémente aussi `tokenVersion` : sans ça,
   * un JWT déjà émis avant le reset resterait valide jusqu'à expiration
   * malgré l'action de l'admin (audit V1 §1).
   */
  async adminResetPin(commercantId: string): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.pinHash = null;
    await this.commercants.save(commercant);
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
  }

  /**
   * Suppression de compte par le commerçant lui-même — soft delete
   * uniquement (`deletedAt`), jamais de suppression physique (conserve
   * l'historique promos/signalements). `tokenVersion` incrémenté pour
   * révoquer immédiatement le token en cours (même mécanisme que
   * `adminResetPin`) : sans ça, la session active resterait valide jusqu'à
   * expiration malgré la suppression. Les promos du commerçant cessent
   * d'être visibles aux clients dès ce moment (filtre `commercant.deletedAt
   * IS NULL` dans `PromoService.findActiveForClient`).
   */
  async deleteAccount(commercantId: string): Promise<void> {
    await this.commercants.update({ id: commercantId }, { deletedAt: new Date() });
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
  }

  /**
   * Édition du profil par le commerçant lui-même — téléphone non modifiable
   * ici. `dto` (transformé par `ValidationPipe`) porte une propriété propre
   * `undefined` pour chaque champ optionnel non fourni (comportement
   * TypeScript `useDefineForClassFields`, actif dès la cible ES2022) — un
   * `Object.assign(commercant, dto)` direct écraserait donc les valeurs déjà
   * en base des champs non envoyés. TypeORM ignore ces `undefined` dans le
   * `UPDATE` SQL (la base reste correcte), mais pas l'objet renvoyé au
   * client : `nom`/`categorie` disparaissaient silencieusement de la
   * réponse dès qu'un appel ne modifiait que `photoKey` (ex. l'envoi de la
   * photo du commerce pendant l'inscription), faisant planter le parsing
   * mobile alors que rien n'était perdu en base (bug trouvé 2026-07-12).
   */
  async updateProfile(
    commercantId: string,
    dto: UpdateCommercantDto,
  ): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(commercantId);
    const previousPhotoKey = commercant.photoKey;
    const definedFields = Object.fromEntries(
      Object.entries(dto).filter(([, value]) => value !== undefined),
    );
    Object.assign(commercant, definedFields);
    // Toute modification de profil repasse par une validation admin avant
    // de pouvoir publier — decision produit 2026-07-12, s'applique à tous
    // les commerçants (voir doc sur la colonne). Posé même si `dto` ne
    // porte qu'un seul champ (ex. juste la photo pendant l'inscription).
    if (Object.keys(definedFields).length > 0) {
      commercant.profilePendingReview = true;
    }
    const saved = await this.commercants.save(commercant);
    // Remplacement de photo : l'ancienne devient orpheline dans S3 si on ne
    // la supprime pas explicitement (buildKey génère toujours une nouvelle
    // clé UUID, jamais un remplacement en place).
    if (dto.photoKey && previousPhotoKey && dto.photoKey !== previousPhotoKey) {
      await this.storageService.deleteObject(previousPhotoKey);
    }
    return saved;
  }

  /**
   * Validation admin d'une modification de profil — remet
   * `profilePendingReview` à `false`, débloque la publication de promo.
   * Pas de "rejet" symétrique au registre : une modification de profil
   * n'est pas un document à accepter/refuser, l'admin peut toujours
   * suspendre le compte séparément s'il juge le changement problématique.
   */
  async validateProfile(commercantId: string): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.profilePendingReview = false;
    await this.commercants.save(commercant);
    await this.notificationService.create(
      NotificationType.PROFILE_VALIDATED,
      NotificationRecipientType.COMMERCANT,
      commercantId,
      'Les modifications de votre profil ont été validées par un administrateur.',
    );
  }

  async findByIdOrFail(id: string): Promise<Commercant> {
    const commercant = await this.commercants.findOne({ where: { id } });
    if (!commercant) {
      throw new NotFoundAppException(ErrorCode.COMMERCANT_NOT_FOUND, 'Commerçant introuvable');
    }
    return commercant;
  }

  async findPublicProfile(id: string): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(id);
    // Contrairement aux endpoints authentifiés (déjà bloqués par la
    // révocation de tokenVersion au moment de la suppression), celui-ci est
    // atteignable par n'importe quel client à partir d'un id mémorisé avant
    // la suppression (favoris, lien de partage) — vérification explicite.
    if (commercant.deletedAt) {
      throw new NotFoundAppException(ErrorCode.COMMERCANT_NOT_FOUND, 'Commerçant introuvable');
    }
    return commercant;
  }

  /**
   * Vérifie que `registreKey` a bien été uploadée par ce commerçant
   * (préfixe `registre-documents/{commercantId}/` posé par
   * `StorageService.buildKey`), avant de la faire passer en attente de
   * validation admin — sans ça, rien n'empêchait un commerçant de soumettre
   * une clé arbitraire, y compris celle d'un tiers (audit sécurité
   * 2026-07-11).
   */
  async requestRegistreVerification(
    commercantId: string,
    registreKey: string,
  ): Promise<void> {
    if (!registreKey.startsWith(`registre-documents/${commercantId}/`)) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_REGISTRE_KEY_MISMATCH,
        "Ce document n'appartient pas à ce commerçant",
      );
    }
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.registreKey = registreKey;
    commercant.registreStatus = RegistreStatus.EN_ATTENTE;
    await this.commercants.save(commercant);
  }

  /**
   * Décision admin sur le registre — conditionne la publication de promos
   * pour un commerçant auto-inscrit depuis le 2026-07-11 (voir
   * `assertRegistreValidated`), ne concerne jamais un commerçant confirmé
   * par un agent (déjà vérifié en personne). Rejouable à tout moment
   * (valider un rejet, rejeter une validation) tant qu'un document a été
   * soumis au moins une fois — jusqu'au 2026-07-12, un rejet était
   * définitif côté admin (seul le commerçant pouvait rouvrir le dossier en
   * renvoyant une photo), ce qui bloquait la correction d'une erreur de
   * modération sans repasser par le commerçant. Purge aussi
   * `profilePendingReview` (2026-07-12) : à l'inscription d'un auto-inscrit,
   * l'envoi de la photo boutique passe par `updateProfile` et allume ce
   * flag en même temps que le registre — sans ce nettoyage, l'admin devrait
   * valider deux fois (registre puis profil) pour un seul nouveau compte.
   * N'affecte jamais un `confirmé_agent` (n'a pas de `registreStatus`, ce
   * chemin ne s'exécute donc jamais pour lui).
   */
  async resolveRegistreVerification(
    commercantId: string,
    approve: boolean,
  ): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (commercant.registreStatus === null) {
      throw new BadRequestAppException(
        ErrorCode.COMMERCANT_NO_PENDING_REGISTRE_VERIFICATION,
        'Aucun registre soumis pour ce commerçant',
      );
    }

    commercant.registreStatus = approve
      ? RegistreStatus.VALIDE
      : RegistreStatus.REJETE;
    commercant.registreValidatedAt = approve ? new Date() : null;
    commercant.profilePendingReview = false;
    await this.commercants.save(commercant);

    // Sans notification, le seul moyen de découvrir une validation/un rejet
    // était de rouvrir le dashboard — pourtant l'événement le plus bloquant
    // pour un commerçant auto-inscrit (audit fonctionnel 2026-07-11).
    await this.notificationService.create(
      approve ? NotificationType.REGISTRE_VALIDATED : NotificationType.REGISTRE_REJECTED,
      NotificationRecipientType.COMMERCANT,
      commercantId,
      approve
        ? 'Votre registre de commerce a été validé — vous pouvez maintenant publier vos promos.'
        : "Votre registre de commerce a été rejeté. Vérifiez la photo envoyée et renvoyez-la depuis votre espace commerçant.",
    );
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
   * Commerces des communes couvertes par un agent, avec statut de tournée
   * (specs §3.3). Faute d'un horodatage explicite de "dernière visite" dans
   * les specs, le statut est dérivé de l'état des promos : jamais publié /
   * a une promo visible / n'a plus que des promos expirées ou masquées.
   *
   * Deux requêtes agrégées (pas une par commerçant) : le statut "à jour"
   * doit utiliser la même définition de "promo visible" que le client
   * (`lifecycleStatus = publiee` + `VISIBLE_MODERATION_STATUSES`), pas
   * seulement `publiee` — sinon une promo `verifiee_ok` fait apparaître à
   * tort le commerçant comme "à relancer".
   */
  async listByCommunesWithVisitStatus(
    communeIds: string[],
  ): Promise<Array<Commercant & { visitStatus: CommuneCommerceStatus }>> {
    if (communeIds.length === 0) return [];
    const commercants = await this.commercants.find({
      where: { communeId: In(communeIds) },
    });
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
      .andWhere('promo.lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .andWhere('promo.moderationStatus IN (:...moderationStatuses)', {
        moderationStatuses: VISIBLE_MODERATION_STATUSES,
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

      let visitStatus: CommuneCommerceStatus;
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

  /** Registres en attente de validation (stat dashboard admin, plan de correction). */
  async countPendingRegistre(): Promise<number> {
    return this.commercants.count({
      where: { registreStatus: RegistreStatus.EN_ATTENTE },
    });
  }

  /** Modifications de profil en attente de validation (stat dashboard admin). */
  async countPendingProfileReview(): Promise<number> {
    return this.commercants.count({ where: { profilePendingReview: true } });
  }

  /**
   * Vue admin (plan de correction, Phase 2) : recherche + liste sur
   * l'ensemble des commerçants, y compris suspendus (`deletedAt` non nul)
   * — sans ça, l'admin ne pourrait jamais retrouver un compte suspendu pour
   * le réactiver.
   */
  async findAllForAdmin(
    query: ListCommercantQueryDto,
  ): Promise<PaginatedResult<Commercant>> {
    const qb = this.commercants
      .createQueryBuilder('commercant')
      .orderBy('commercant.createdAt', 'DESC');

    if (query.search) {
      qb.andWhere(
        '(commercant.nom ILIKE :search OR commercant.telephone ILIKE :search)',
        { search: `%${query.search}%` },
      );
    }
    if (query.accountState) {
      qb.andWhere('commercant.accountState = :accountState', {
        accountState: query.accountState,
      });
    }
    if (query.registreStatus) {
      qb.andWhere('commercant.registreStatus = :registreStatus', {
        registreStatus: query.registreStatus,
      });
    }
    if (query.profilePendingReview !== undefined) {
      qb.andWhere('commercant.profilePendingReview = :profilePendingReview', {
        profilePendingReview: query.profilePendingReview,
      });
    }
    qb.skip((query.page - 1) * query.limit).take(query.limit);

    const [items, total] = await qb.getManyAndCount();
    return toPaginatedResult(items, total, query.page, query.limit);
  }

  /**
   * Réactivation d'un compte suspendu par l'admin — symétrique de
   * `deleteAccount`, sans changement de `tokenVersion` (réactiver ne révoque
   * rien, ça ne fait que rouvrir l'accès à la connexion).
   */
  async reactivateAccount(commercantId: string): Promise<void> {
    await this.commercants.update({ id: commercantId }, { deletedAt: null });
  }

  /** Garde IDOR : un agent ne peut agir que sur les commerçants de ses propres communes. */
  async assertCommuneMatches(
    commercantId: string,
    agentCommuneIds: string[],
  ): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (!agentCommuneIds.includes(commercant.communeId)) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_NOT_IN_AGENT_COMMUNES,
        "Ce commerçant n'est dans aucune des communes de cet agent",
      );
    }
    return commercant;
  }

  /**
   * Un commerçant auto-inscrit (`AUTO_INSCRIT`) ne peut créer/publier de
   * promo qu'une fois son registre de commerce validé par un admin —
   * décision produit du 2026-07-11, qui remplace le badge `vérifié_registre`
   * non-bloquant prévu aux specs §3.2/§5.4 (revert assumé : ne plus laisser
   * publier un compte non vérifié). Un commerçant créé par un agent
   * (`CONFIRME_AGENT`) est déjà vérifié en personne et n'est jamais
   * concerné par cette garde.
   */
  assertRegistreValidated(commercant: Commercant): void {
    if (
      commercant.originVerification === CommercantOriginVerification.AUTO_INSCRIT &&
      commercant.registreStatus !== RegistreStatus.VALIDE
    ) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED,
        'Votre registre de commerce doit être validé par un administrateur avant de pouvoir publier des promos',
      );
    }
  }

  /**
   * Contrairement à `assertRegistreValidated`, s'applique à **tous** les
   * commerçants sans exception d'origine — décision produit du 2026-07-12 :
   * toute modification de profil (même pour un commerçant confirmé par un
   * agent) repasse par un contrôle admin avant de pouvoir publier.
   */
  assertProfileValidated(commercant: Commercant): void {
    if (commercant.profilePendingReview) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_PROFILE_PENDING_REVIEW,
        'Les modifications de votre profil doivent être validées par un administrateur avant de pouvoir publier des promos',
      );
    }
  }
}

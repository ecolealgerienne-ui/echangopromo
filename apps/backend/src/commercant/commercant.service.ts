import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, QueryFailedError, Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import {
  BadRequestAppException,
  ConflictAppException,
  ForbiddenAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import {
  PaginatedResult,
  toPaginatedResult,
} from '../common/pagination/paginated-result';
import {
  NotificationRecipientType,
  NotificationType,
} from '../notification/entities/notification.entity';
import { NotificationService } from '../notification/notification.service';
import { Promo, PromoLifecycleStatus } from '../promo/entities/promo.entity';
import { StorageService } from '../storage/storage.service';
import { CommercantView } from './entities/commercant-view.entity';
import {
  Commercant,
  CommercantAccountState,
  CommercantOriginVerification,
  RegistreStatus,
} from './entities/commercant.entity';
import { CreateCommercantByAgentDto } from './dto/create-commercant-by-agent.dto';
import { ListCommercantQueryDto } from './dto/list-commercant-query.dto';
import { RegisterCommercantDto } from './dto/register-commercant.dto';
import { SetCommercantPositionDto } from './dto/set-position.dto';
import { UpdateCommercantDto } from './dto/update-commercant.dto';

@Injectable()
export class CommercantService {
  constructor(
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    @InjectRepository(CommercantView)
    private readonly views: Repository<CommercantView>,
    // Accès direct à l'entité Promo pour la cascade de statut posée par
    // suspend/deleteCommercant/deleteAccount — voir le commentaire dans
    // commercant.module.ts (cycle NestJS avec PromoModule sinon).
    @InjectRepository(Promo)
    private readonly promos: Repository<Promo>,
    private readonly authService: AuthService,
    private readonly storageService: StorageService,
    private readonly notificationService: NotificationService,
  ) {}

  /**
   * **Le seul endroit qui sait comment retrouver un compte par son numéro.**
   *
   * Un numéro n'identifie un compte que parmi les **non supprimés** : la
   * suppression est douce (`deletedAt`), la ligne reste en base, et le numéro
   * redevient attribuable — plusieurs lignes peuvent donc porter le même
   * numéro, dont une seule vivante. C'est le filtre de l'index partiel posé en
   * base (voir `Commercant.telephone`).
   *
   * ⚠️ **Pourquoi une méthode et non un filtre recopié.** Ce filtre a vécu
   * deux fois : appliqué dans `assertPhoneAvailable`, oublié dans `login`. Le
   * commentaire disait pourtant « même filtre que l'index partiel » — une
   * phrase ne tient pas un invariant. Conséquence, trouvée le 2026-08-04 :
   * après un cycle suppression → réinscription, `login` retrouvait la ligne
   * **supprimée**, voyait son `deletedAt` et refusait — le repreneur du numéro
   * ne pouvait **jamais** se connecter, alors que son inscription avait
   * réussi. Un seul endroit désormais (CLAUDE.md règle 30).
   *
   * ⚠️ Un compte **suspendu** garde son numéro : seule la suppression le
   * libère (décision produit 2026-07-14, suspension et suppression sont deux
   * états distincts).
   */
  private async findVivantByTelephone(
    telephone: string,
  ): Promise<Commercant | null> {
    return this.commercants.findOne({
      where: { telephone, deletedAt: IsNull() },
    });
  }

  private async assertPhoneAvailable(telephone: string): Promise<void> {
    const existing = await this.findVivantByTelephone(telephone);
    if (existing) {
      throw new ConflictAppException(
        ErrorCode.COMMERCANT_PHONE_TAKEN,
        'Ce numéro de téléphone est déjà enregistré',
      );
    }
  }

  /**
   * `assertPhoneAvailable` est un « vérifier puis insérer » (règle #13) : deux
   * inscriptions simultanées sur le même numéro lisent toutes les deux
   * « libre », et la seconde heurte l'index unique partiel
   * `UQ_commercant_telephone_active`. Ce `23505` n'était rattrapé **nulle
   * part** dans le backend — il remontait en 500 `INTERNAL_ERROR`, laissant
   * croire à une panne là où le refus métier existe déjà et est traduit dans
   * les trois langues (revue 2026-08-05).
   *
   * Le nom de l'index est vérifié plutôt que le seul code `23505` : une autre
   * contrainte d'unicité ajoutée plus tard ne doit pas se retrouver déguisée
   * en « numéro déjà pris ».
   */
  private async saveNewAccount(commercant: Commercant): Promise<Commercant> {
    try {
      return await this.commercants.save(commercant);
    } catch (error) {
      const driverError = (error as QueryFailedError)?.driverError as {
        code?: string;
        constraint?: string;
      };
      if (
        error instanceof QueryFailedError &&
        driverError?.code === '23505' &&
        driverError.constraint === 'UQ_commercant_telephone_active'
      ) {
        throw new ConflictAppException(
          ErrorCode.COMMERCANT_PHONE_TAKEN,
          'Ce numéro de téléphone est déjà enregistré',
        );
      }
      throw error;
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
    return this.saveNewAccount(
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

  /**
   * Création assistée par l'agent (specs §3.2, voie 2). L'agent choisit et
   * transmet le PIN en personne (décision produit 2026-07-13) : le compte
   * est `autonome` dès la création, plus d'état intermédiaire `cree_agent`
   * en attente d'une revendication publique (ancienne faille — un tiers
   * connaissant seulement le numéro de téléphone du commerçant pouvait
   * revendiquer le compte avant lui).
   */
  async createByAgent(
    dto: CreateCommercantByAgentDto,
    agentId: string,
  ): Promise<Commercant> {
    await this.assertPhoneAvailable(dto.telephone);
    const { pin, ...rest } = dto;

    return this.saveNewAccount(
      this.commercants.create({
        ...rest,
        pinHash: await this.authService.hash(pin),
        createdByAgentId: agentId,
        accountState: CommercantAccountState.AUTONOME,
        originVerification: CommercantOriginVerification.CONFIRME_AGENT,
      }),
    );
  }

  async login(telephone: string, pin: string): Promise<Commercant> {
    const commercant = await this.findVivantByTelephone(telephone);
    // Un compte suspendu (`suspendedAt`) est traité comme des identifiants
    // invalides plutôt qu'un message dédié — évite de confirmer à un tiers que
    // ce numéro a un jour eu un compte, et bloque effectivement la connexion
    // pendant une suspension. Les comptes supprimés, eux, ne sont même pas
    // retrouvés : `findVivantByTelephone` les exclut.
    if (!commercant?.pinHash || commercant.suspendedAt) {
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
   * PIN vraiment oublié (le commerçant ne peut fournir aucun ancien PIN) —
   * l'admin/agent fixe directement un nouveau PIN (décision produit
   * 2026-07-13, remplace l'ancienne remise à zéro suivie d'une
   * revendication publique, qui laissait n'importe qui connaissant le
   * numéro de téléphone s'approprier le compte en premier). Incrémente
   * `tokenVersion` : sans ça, un JWT déjà émis avant le reset resterait
   * valide jusqu'à expiration malgré l'action de l'admin (audit V1 §1).
   */
  async resetPin(commercantId: string, newPin: string): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    commercant.pinHash = await this.authService.hash(newPin);
    await this.commercants.save(commercant);
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
  }

  /**
   * Le commerçant se souvient encore de son PIN actuel et veut le changer
   * — libre-service (`CommercantController.changeMyPin`, décision produit
   * 2026-07-13) : la preuve de possession de l'ancien PIN tient lieu de
   * vérification d'identité, sans OTP. Distinct de `resetPin` ci-dessus
   * (PIN vraiment oublié, admin/agent seuls).
   */
  async changePin(
    commercantId: string,
    oldPin: string,
    newPin: string,
  ): Promise<void> {
    const commercant = await this.findByIdOrFail(commercantId);
    if (
      !commercant.pinHash ||
      !(await this.authService.compare(oldPin, commercant.pinHash))
    ) {
      throw new BadRequestAppException(
        ErrorCode.COMMERCANT_OLD_PIN_MISMATCH,
        "L'ancien PIN ne correspond pas",
      );
    }
    commercant.pinHash = await this.authService.hash(newPin);
    await this.commercants.save(commercant);
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
  }

  /**
   * Suppression de compte par le commerçant lui-même — soft delete
   * uniquement (`deletedAt`), jamais de suppression physique (conserve
   * l'historique promos/signalements). Libère le numéro de téléphone (voir
   * `assertPhoneAvailable`) et "supprime" (`PromoLifecycleStatus.SUPPRIMEE`,
   * pas de suppression physique non plus) toutes les promos du commerçant —
   * mêmes règles que `deleteCommercant` (admin/agent), décision produit
   * 2026-07-14. `tokenVersion` incrémenté pour révoquer immédiatement le
   * token en cours (même mécanisme que `resetPin`/`changePin`) : sans ça, la
   * session active resterait valide jusqu'à expiration malgré la
   * suppression.
   */
  async deleteAccount(commercantId: string): Promise<void> {
    await this.commercants.update(
      { id: commercantId },
      { deletedAt: new Date() },
    );
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
    await this.promos.update(
      { commercantId },
      { lifecycleStatus: PromoLifecycleStatus.SUPPRIMEE },
    );
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
    // `photoKey` revient du client et la clé d'un tiers est publique
    // (`GET /commercant/:id/public` sert `photoUrl`, donc la clé littérale) :
    // sans cette garde, poser la clé d'un concurrent puis la remplacer d'un
    // second PATCH la faisait supprimer de S3 par le `deleteObject` ci-dessous
    // — et l'affichait sur sa propre fiche entre les deux (revue 2026-08-05).
    // `requestRegistreVerification` fait déjà exactement ce contrôle sur
    // `registreKey`, deux méthodes plus bas : c'est la règle #10, une garde
    // écrite mais non appliquée aux autres champs de clé.
    if (dto.photoKey) {
      this.storageService.assertKeyOwnedBy(dto.photoKey, 'commercant-photos', [
        commercantId,
      ]);
    }
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
      throw new NotFoundAppException(
        ErrorCode.COMMERCANT_NOT_FOUND,
        'Commerçant introuvable',
      );
    }
    return commercant;
  }

  async findPublicProfile(id: string): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(id);
    // Contrairement aux endpoints authentifiés (déjà bloqués par la
    // révocation de tokenVersion au moment de la suppression/suspension),
    // celui-ci est atteignable par n'importe quel client à partir d'un id
    // mémorisé avant (favoris, lien de partage) — vérification explicite.
    if (commercant.deletedAt || commercant.suspendedAt) {
      throw new NotFoundAppException(
        ErrorCode.COMMERCANT_NOT_FOUND,
        'Commerçant introuvable',
      );
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
      approve
        ? NotificationType.REGISTRE_VALIDATED
        : NotificationType.REGISTRE_REJECTED,
      NotificationRecipientType.COMMERCANT,
      commercantId,
      approve
        ? 'Votre registre de commerce a été validé — vous pouvez maintenant publier vos promos.'
        : 'Votre registre de commerce a été rejeté. Vérifiez la photo envoyée et renvoyez-la depuis votre espace commerçant.',
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
   * `communeIds` restreint aux communes d'un agent (dashboard partagé
   * admin/agent, décision produit 2026-07-12) — `undefined` = vue globale
   * (admin), même convention que `AdminController.scopedCommuneIds`.
   */
  /**
   * **Le filtre « compte vivant » commun à tous les compteurs de dashboard.**
   *
   * Le bug avait été trouvé le 2026-07-14 et corrigé sur `countActive`
   * **seul** — les deux autres compteurs recopiaient le même `where` sans
   * lui, et gardaient donc leurs anomalies : un `registresEnAttente: 1`
   * affiché indéfiniment pour un compte supprimé, que le vider notifiait un
   * destinataire mort (revue 2026-08-05, règle #9 — trois copies d'une même
   * règle, une seule corrigée).
   *
   * Un compte **suspendu** est exclu au même titre qu'un supprimé : ces
   * compteurs comptent ce qu'un admin doit traiter, et un compte suspendu
   * n'attend pas une validation de registre mais une décision de
   * réactivation, qui rendra son dossier à la file.
   */
  private aliveAccountWhere(communeIds?: string[]) {
    return {
      deletedAt: IsNull(),
      suspendedAt: IsNull(),
      ...(communeIds ? { communeId: In(communeIds) } : {}),
    };
  }

  async countActive(communeIds?: string[]): Promise<number> {
    if (communeIds && communeIds.length === 0) return 0;
    return this.commercants.count({
      where: {
        accountState: CommercantAccountState.AUTONOME,
        ...this.aliveAccountWhere(communeIds),
      },
    });
  }

  /** Registres en attente de validation (stat dashboard admin, plan de correction). */
  async countPendingRegistre(communeIds?: string[]): Promise<number> {
    if (communeIds && communeIds.length === 0) return 0;
    return this.commercants.count({
      where: {
        registreStatus: RegistreStatus.EN_ATTENTE,
        ...this.aliveAccountWhere(communeIds),
      },
    });
  }

  /** Modifications de profil en attente de validation (stat dashboard admin). */
  async countPendingProfileReview(communeIds?: string[]): Promise<number> {
    if (communeIds && communeIds.length === 0) return 0;
    return this.commercants.count({
      where: {
        profilePendingReview: true,
        ...this.aliveAccountWhere(communeIds),
      },
    });
  }

  /**
   * Vue admin (plan de correction, Phase 2) : recherche + liste sur
   * l'ensemble des commerçants, y compris suspendus et supprimés — sans ça,
   * l'admin ne pourrait jamais retrouver un compte suspendu pour le
   * réactiver, ni consulter l'historique d'un compte supprimé. `communeIds`
   * restreint aux communes d'un agent (partage de cet écran admin/agent,
   * décision produit 2026-07-12) — `undefined` = vue globale (admin).
   */
  async findAllForAdmin(
    query: ListCommercantQueryDto,
    communeIds?: string[],
  ): Promise<PaginatedResult<Commercant>> {
    if (communeIds && communeIds.length === 0) {
      return toPaginatedResult([], 0, query.page, query.limit);
    }

    const qb = this.commercants
      .createQueryBuilder('commercant')
      .orderBy('commercant.createdAt', 'DESC');

    if (communeIds) {
      qb.andWhere('commercant.communeId IN (:...communeIds)', { communeIds });
    }
    if (query.communeId) {
      qb.andWhere('commercant.communeId = :filterCommuneId', {
        filterCommuneId: query.communeId,
      });
    }
    if (query.wilaya) {
      qb.innerJoin('commercant.commune', 'commune').andWhere(
        'commune.wilaya = :wilaya',
        {
          wilaya: query.wilaya,
        },
      );
    }
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
   * Suspension par l'admin/agent — réversible et arbitraire (aucun motif
   * métier requis), distincte de `deleteCommercant`/`deleteAccount`
   * (décision produit 2026-07-14) : ne touche jamais `deletedAt`, ne libère
   * donc jamais le numéro de téléphone. Dépublie les promos en cours
   * (`PUBLIEE` → `BROUILLON`, pas `SUPPRIMEE` — réversible) et révoque la
   * session en cours comme tout changement d'état de sécurité (règle #6),
   * pour empêcher un commerçant déjà connecté de continuer à publier
   * pendant sa suspension.
   */
  async suspend(commercantId: string): Promise<void> {
    await this.findByIdOrFail(commercantId);
    await this.commercants.update(
      { id: commercantId },
      { suspendedAt: new Date() },
    );
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
    await this.promos.update(
      { commercantId, lifecycleStatus: PromoLifecycleStatus.PUBLIEE },
      { lifecycleStatus: PromoLifecycleStatus.BROUILLON },
    );
  }

  /**
   * Lève une suspension — pas de republication automatique des promos
   * repassées en `BROUILLON` (décision produit 2026-07-14) : le commerçant
   * les republie lui-même après avoir vérifié qu'elles sont toujours à jour
   * (prix, dates). Le numéro de téléphone n'ayant jamais été libéré par la
   * suspension, aucune vérification de collision n'est nécessaire ici
   * (contrairement à une éventuelle restauration après suppression, non
   * supportée : le numéro peut entre-temps avoir été réattribué).
   */
  async unsuspend(commercantId: string): Promise<void> {
    await this.findByIdOrFail(commercantId);
    await this.commercants.update({ id: commercantId }, { suspendedAt: null });
  }

  /**
   * Fixe le plafond de promos actives propre à ce commerçant, ou le remet sur
   * le réglage global avec `null`.
   *
   * ⚠️ **N'agit sur aucune promo déjà en ligne.** Abaisser le plafond de 5 à 2
   * ne dépublie rien : il empêche les prochaines publications jusqu'à ce que
   * le compte redescende sous la nouvelle valeur. Dépublier d'autorité serait
   * une sanction, pas un réglage — et la sanction a déjà son geste
   * (`suspend`), qui, lui, repasse les promos en brouillon.
   */
  async setPromoActiveCap(
    commercantId: string,
    plafond: number | null,
  ): Promise<void> {
    await this.findByIdOrFail(commercantId);
    await this.commercants.update(
      { id: commercantId },
      { promoActiveCap: plafond },
    );
  }

  /**
   * Suppression par l'admin/agent — même effet que l'auto-suppression du
   * commerçant (`deleteAccount`), déclenchée cette fois par l'admin/agent
   * (compte frauduleux, commerce fermé, changement de propriétaire...).
   * Libère le numéro de téléphone et "supprime" toutes les promos du
   * commerçant. Pas de restauration prévue.
   */
  async deleteCommercant(commercantId: string): Promise<void> {
    await this.findByIdOrFail(commercantId);
    await this.commercants.update(
      { id: commercantId },
      { deletedAt: new Date() },
    );
    await this.commercants.increment({ id: commercantId }, 'tokenVersion', 1);
    await this.promos.update(
      { commercantId },
      { lifecycleStatus: PromoLifecycleStatus.SUPPRIMEE },
    );
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
      commercant.originVerification ===
        CommercantOriginVerification.AUTO_INSCRIT &&
      commercant.registreStatus !== RegistreStatus.VALIDE
    ) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_REGISTRE_NOT_VALIDATED,
        'Votre registre de commerce doit être validé par un administrateur avant de pouvoir publier des promos',
      );
    }
  }

  /**
   * Pose la position du commerce, **sans déclencher la revue de profil quand
   * il n'y en avait aucune**.
   *
   * C'est la sortie de l'impasse décrite dans `SetCommercantPositionDto` : le
   * commerçant bloqué faute de position doit pouvoir se débloquer **seul**, or
   * la route générale de profil le renverrait attendre un administrateur.
   *
   * ⚠️ **L'exception ne vaut que pour la première pose.** Un commerçant qui
   * *déplace* une position déjà renseignée décrit un commerce qui a changé
   * d'adresse — exactement ce que la revue admin existe pour regarder. Ce
   * `wasUnset` est donc la frontière entre « réparer une donnée manquante » et
   * « modifier son profil », et l'élargir viderait la revue de son objet.
   */
  async setPosition(
    commercantId: string,
    dto: SetCommercantPositionDto,
  ): Promise<Commercant> {
    const commercant = await this.findByIdOrFail(commercantId);
    const wasUnset =
      commercant.latitude === null || commercant.longitude === null;
    commercant.latitude = dto.latitude;
    commercant.longitude = dto.longitude;
    if (!wasUnset) {
      commercant.profilePendingReview = true;
    }
    return this.commercants.save(commercant);
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

  /**
   * Sans position, une promo n'est **visible par personne** : les clients
   * cherchent par proximité et la carte filtre sur un cadre, qu'un `NULL` ne
   * peut pas satisfaire. Publier serait donc un geste sans effet — et sans
   * cette garde, le commerçant verrait « 3 en ligne » sur un stock que
   * personne ne voit, exactement le défaut que `countVisible` avait déjà
   * produit une fois (règle #8).
   *
   * ⚠️ **`=== null`, pas la véracité.** `!commercant.longitude` refuserait une
   * longitude à `0`, qui est le méridien de Greenwich — une coordonnée
   * parfaitement légitime. Même piège que `configNumber` côté configuration.
   *
   * ⚠️ **Ne jamais appeler cette garde sur un enregistrement en brouillon.**
   * `promo.service.ts` documente la régression exacte qu'on refabriquerait :
   * des gardes posées pour tout le monde refusaient aussi « Enregistrer comme
   * brouillon », « avec un message parlant de publier, sur un geste qui ne
   * publie pas ». Un commerçant sans position doit pouvoir **préparer** ses
   * promos ; c'est les mettre en ligne qui exige un point.
   */
  assertPositionSet(commercant: Commercant): void {
    if (commercant.latitude === null || commercant.longitude === null) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_POSITION_REQUIRED,
        'Indiquez la position de votre commerce pour pouvoir publier : les clients cherchent les promos autour d’eux',
      );
    }
  }

  /**
   * Compte supprimé ou suspendu (soft dans les deux cas). Le commerçant
   * lui-même est déjà arrêté en amont — suspension et suppression révoquent
   * son token (`tokenVersion`) — mais **pas l'agent ni l'admin**, qui
   * agissent avec le leur : `PromoService.create`/`publish` acceptaient donc
   * de republier pour un commerçant suspendu, défaisant la cascade qui venait
   * de repasser ses promos en brouillon (revue 2026-08-05). Invisible côté
   * client grâce aux gardes défensives des lectures, mais l'état en base
   * contredisait alors la décision de modération.
   */
  assertAccountActive(commercant: Commercant): void {
    if (commercant.deletedAt || commercant.suspendedAt) {
      throw new ForbiddenAppException(
        ErrorCode.COMMERCANT_ACCOUNT_INACTIVE,
        'Ce compte commerçant est suspendu ou supprimé',
      );
    }
  }
}

import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import {
  Between,
  EntityManager,
  In,
  IsNull,
  LessThan,
  MoreThan,
  Not,
  Repository,
  SelectQueryBuilder,
} from 'typeorm';
import { CommercantService } from '../commercant/commercant.service';
import { Commercant } from '../commercant/entities/commercant.entity';
import {
  BadRequestAppException,
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
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoAdminQueryDto } from './dto/list-promo-admin-query.dto';
import { ListPromoMapQueryDto } from './dto/list-promo-map-query.dto';
import { ListPromoQueryDto, PromoSortOrder } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { PromoView } from './entities/promo-view.entity';
import {
  Promo,
  PromoLifecycleStatus,
  PromoModerationStatus,
  VISIBLE_MODERATION_STATUSES,
} from './entities/promo.entity';

const MAX_PROMOS_ACTIVES = 5;

/**
 * Fenêtre « expire bientôt », alignée sur la cadence quotidienne du cron :
 * chaque promo ne peut la croiser qu'une fois (pas de doublon, pas de promo
 * manquée).
 *
 * ⚠️ **Recopiée côté app** (`Promo.isExpiringSoon`, qui allume le badge). Le
 * commentaire mobile affirmait « une seule définition de bientôt dans tout le
 * produit » — il y en avait deux, et rien ne les tenait : changer la cadence
 * du cron aurait fait afficher le badge sans notification correspondante,
 * ou l'inverse. Nommée des deux côtés et tenue par
 * `apps/mobile/tool/check_server_rules.dart` depuis le 2026-08-05 (règle #30).
 */
const EXPIRING_SOON_WINDOW_HOURS = 24;

/**
 * Plafond de commerçants renvoyés pour une zone de carte. Au-delà, la carte
 * serait de toute façon illisible et la réponse inutilement lourde : le
 * client reçoit `truncated: true` et invite à zoomer, plutôt que de perdre
 * silencieusement des commerces (règle d'audit #15).
 */
const MAX_MAP_COMMERCANTS = 300;

@Injectable()
export class PromoService {
  private readonly logger = new Logger(PromoService.name);

  constructor(
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
    @InjectRepository(PromoView) private readonly views: Repository<PromoView>,
    private readonly commercantService: CommercantService,
    private readonly storageService: StorageService,
    private readonly configService: ConfigService,
    private readonly notificationService: NotificationService,
  ) {}

  private defaultDureeJours(): number {
    return this.configService.get<number>('PROMO_DEFAULT_DURATION_DAYS', 5);
  }

  private maxDureeJours(): number {
    return this.configService.get<number>('PROMO_MAX_DURATION_DAYS', 7);
  }

  private imageRetentionDays(): number {
    return this.configService.get<number>('IMAGE_RETENTION_DAYS', 30);
  }

  /** Anti-abus (retour terrain 2026-07-14) — voir `assertUnderDailyCreationCap`. */
  private dailyCreationCap(): number {
    return this.configService.get<number>('PROMO_DAILY_CREATION_CAP', 5);
  }

  /** Anti-abus (retour terrain 2026-07-14) — voir `assertRepublishCooldown`. */
  private republishCooldownHours(): number {
    return this.configService.get<number>('PROMO_REPUBLISH_COOLDOWN_HOURS', 24);
  }

  /**
   * **L'unique définition de « promo visible par un client ».**
   *
   * Cinq conditions orthogonales : publiée, modération non bloquante, non
   * expirée, commerçant ni supprimé ni suspendu. Elles étaient recopiées dans
   * quatre méthodes et appliquées partiellement dans une cinquième — la revue
   * du 2026-08-05 a trouvé `countVisible` sans les deux gardes commerçant
   * (une promo republiée pour un compte suspendu comptait au dashboard sans
   * qu'aucun client ne la voie) et `PromoController.detail` avec **une seule**
   * des cinq (un lien partagé servait encore une promo arrêtée ou expirée).
   * Le commentaire disant « la définition ne vit qu'ici » existait déjà : il
   * ne tenait rien, un commentaire ne pouvant pas échouer (règle #30).
   *
   * Exige que `commercant` soit déjà joint sous cet alias.
   */
  private applyVisibleConditions(
    qb: SelectQueryBuilder<Promo>,
  ): SelectQueryBuilder<Promo> {
    return qb
      .andWhere('promo.lifecycleStatus = :visibleLifecycleStatus', {
        visibleLifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .andWhere('promo.moderationStatus IN (:...visibleModerationStatuses)', {
        visibleModerationStatuses: VISIBLE_MODERATION_STATUSES,
      })
      .andWhere('promo.dateFin > NOW()')
      .andWhere('commercant.deletedAt IS NULL')
      .andWhere('commercant.suspendedAt IS NULL');
  }

  /**
   * Est-elle réellement en ligne *maintenant* ? Le cron d'expiration ne passe
   * qu'à 1h : entre son expiration et ce passage, une promo garde
   * `lifecycleStatus = PUBLIEE` alors qu'elle n'est plus visible nulle part.
   * Sans cette distinction elle occupait quand même un des 5 emplacements et
   * `publish` la refusait en `PROMO_ALREADY_PUBLISHED` — jusqu'à 24 h pendant
   * lesquelles le commerçant ne pouvait ni la republier ni en créer une autre
   * (revue 2026-08-05, règle #8 : le cycle de vie ne se lit pas sur le seul
   * enum, la date en fait partie).
   */
  private isEnLigne(promo: Promo): boolean {
    return (
      promo.lifecycleStatus === PromoLifecycleStatus.PUBLIEE &&
      promo.dateFin !== null &&
      promo.dateFin.getTime() > Date.now()
    );
  }

  /**
   * Calcule/valide la date de fin — jamais plus loin que
   * `PROMO_MAX_DURATION_DAYS`.
   *
   * `dureeJours` est la voie **normale** depuis le 2026-08-05 : la date est
   * alors dérivée de l'horloge du serveur, la seule qui valide. `requested`
   * (date absolue calculée par le client) reste accepté pour les clients déjà
   * installés — il perd l'arbitrage quand les deux arrivent.
   */
  private resolveDateFin(requested?: Date, dureeJours?: number): Date {
    const now = Date.now();
    const max = new Date(now + this.maxDureeJours() * 24 * 60 * 60 * 1000);
    const dateFin =
      (dureeJours !== undefined
        ? new Date(now + dureeJours * 24 * 60 * 60 * 1000)
        : requested) ??
      new Date(now + this.defaultDureeJours() * 24 * 60 * 60 * 1000);

    // ⚠️ **Une date invalide passe les deux comparaisons qui suivent.** Un
    // `dureeJours` énorme (1e30) déborde l'intervalle représentable et rend
    // `new Date(...)` → `Invalid Date`, dont `getTime()` vaut `NaN` : `NaN <=
    // now` et `NaN > max` sont **tous les deux faux**, et la date atterrissait
    // en base. Le chemin `dateFin` n'avait pas ce trou (`@IsDate` de
    // class-validator rejette déjà une `Invalid Date`) — c'est l'ajout de
    // `dureeJours` le 2026-08-05 qui l'a ouvert. Toute comparaison numérique
    // sur une valeur venue du réseau doit d'abord établir qu'elle est un
    // nombre.
    if (!Number.isFinite(dateFin.getTime())) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DATE_FIN_EXCEEDS_MAX,
        `La durée demandée dépasse ${this.maxDureeJours()} jours`,
      );
    }
    if (dateFin.getTime() <= now) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DATE_FIN_NOT_FUTURE,
        'La date de fin doit être dans le futur',
      );
    }
    if (dateFin.getTime() > max.getTime()) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DATE_FIN_EXCEEDS_MAX,
        `La date de fin ne peut pas dépasser ${this.maxDureeJours()} jours`,
      );
    }
    return dateFin;
  }

  /**
   * Plafond de 5 promos actives (specs §5.3), compté sur `lifecycleStatus =
   * publiee` uniquement — un brouillon ou une promo arrêtée ne compte pas.
   * Appelé sous verrou consultatif Postgres scopé au commerçant (voir
   * `create`/`publish`) — sans ça, deux publications quasi simultanées
   * peuvent chacune lire un compte de 4 et passer, aboutissant à 6 actives.
   */
  private async assertUnderCap(
    manager: EntityManager,
    commercantId: string,
  ): Promise<void> {
    // `dateFin > maintenant` en plus du statut : une promo expirée mais pas
    // encore basculée par le cron de 1h n'occupe plus d'emplacement (voir
    // `isEnLigne`).
    const activeCount = await manager.count(Promo, {
      where: {
        commercantId,
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        dateFin: MoreThan(new Date()),
      },
    });
    if (activeCount >= MAX_PROMOS_ACTIVES) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_ACTIVE_CAP_REACHED,
        `Plafond de ${MAX_PROMOS_ACTIVES} promos actives atteint pour ce commerçant`,
      );
    }
  }

  /**
   * Anti-abus (retour terrain 2026-07-14) : sans ce plafond, un commerçant
   * pourrait créer une nouvelle promo en boucle rien que pour profiter du
   * tri "plus récentes en premier" côté client (`publishedAt`) — le
   * cooldown de republication (`assertRepublishCooldown`) ne suffit pas
   * seul, puisque créer une NOUVELLE promo à chaque fois le contourne.
   * Compte toutes les créations (brouillon inclus, comme le plafond actif
   * ne les compte pas mais celui-ci le doit) sur une fenêtre glissante de
   * 24h, pas un jour calendaire — pas de contournement en recréant juste
   * après minuit. Même verrou que `assertUnderCap` (règle #13).
   */
  private async assertUnderDailyCreationCap(
    manager: EntityManager,
    commercantId: string,
  ): Promise<void> {
    const cap = this.dailyCreationCap();
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const recentCount = await manager.count(Promo, {
      where: { commercantId, createdAt: MoreThan(since) },
    });
    if (recentCount >= cap) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_DAILY_CREATION_CAP_REACHED,
        `Plafond de ${cap} créations de promo par 24h atteint pour ce commerçant`,
      );
    }
  }

  /**
   * Anti-abus (retour terrain 2026-07-14) : sans ce cooldown, un commerçant
   * pourrait enchaîner des cycles arrêt→republication rien que pour
   * rafraîchir `publishedAt` et remonter en tête du tri "plus récentes en
   * premier" côté client. Ne s'applique qu'à une republication
   * (`publishedAt` déjà posé par une publication précédente) — jamais à la
   * toute première publication d'un brouillon.
   */
  private assertRepublishCooldown(promo: Promo): void {
    if (!promo.publishedAt) return;
    const cooldownMs = this.republishCooldownHours() * 60 * 60 * 1000;
    const nextAllowedAt = new Date(promo.publishedAt.getTime() + cooldownMs);
    if (nextAllowedAt.getTime() > Date.now()) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_REPUBLISH_TOO_SOON,
        `Vous pourrez republier cette promo à partir du ${nextAllowedAt.toISOString()}`,
      );
    }
  }

  /**
   * Les clés de photo arrivent du client dans le DTO et ne sont validées que
   * comme des chaînes non vides — or elles sont publiques (`GET /promo` sert
   * l'URL complète, donc la clé littérale, de n'importe quelle promo). Sans
   * cette garde, un commerçant pouvait poser la clé d'un concurrent sur sa
   * propre promo — l'IDOR de `assertCanManage` restant satisfait, la promo
   * lui appartenant bien — puis la retirer d'un second `PATCH` pour la faire
   * supprimer de S3 par `removedKeys` (revue 2026-08-05, règles #1 et #10).
   *
   * `actorId` : pour une promo créée/éditée par un agent ou un admin, les
   * clés portent le `sub` de l'acteur (voir `StorageController.upload`), pas
   * celui du commerçant — les deux préfixes sont donc légitimes.
   */
  private assertPhotoKeysOwned(
    keys: string[],
    commercantId: string,
    actorId?: string,
  ): void {
    const allowedOwnerIds = actorId ? [commercantId, actorId] : [commercantId];
    for (const key of keys) {
      this.storageService.assertKeyOwnedBy(
        key,
        'promo-photos',
        allowedOwnerIds,
      );
    }
  }

  /**
   * Best-effort : une miniature manquante ne doit jamais bloquer la
   * création/édition d'une promo — `PromoController.toClientJson` retombe
   * sur la photo complète si `null` (échec réseau S3 transitoire par ex.).
   */
  private async tryGenerateThumbnail(
    sourceKey: string,
  ): Promise<string | null> {
    try {
      return await this.storageService.generateThumbnail(sourceKey);
    } catch (error) {
      this.logger.warn(
        `Échec de génération de la miniature pour ${sourceKey} : ${error}`,
      );
      return null;
    }
  }

  private async withCommercantLock<T>(
    commercantId: string,
    fn: (manager: EntityManager) => Promise<T>,
  ): Promise<T> {
    return this.promos.manager.transaction(async (manager) => {
      await manager.query(
        'SELECT pg_advisory_xact_lock(hashtext($1)::bigint)',
        [commercantId],
      );
      return fn(manager);
    });
  }

  /**
   * Création (specs §3.2/§5.3) — `asDraft: true` enregistre en brouillon
   * (non visible, non compté dans le plafond de 5 promos *actives*,
   * `dateFin` non fixée — mais compté dans le plafond anti-abus de
   * créations/24h, voir `assertUnderDailyCreationCap`) ; sinon publie
   * immédiatement (comportement historique, comportement par défaut pour ne
   * rien casser côté agent).
   *
   * `trustedActor` (2026-07-14) : passé à `true` uniquement par
   * `PromoController.createByAgent` (agent/admin, jamais l'auto-inscription
   * commerçant) — ces deux rôles agissent via un canal audité et créé
   * exclusivement par l'admin (pas d'auto-inscription), le vecteur d'abus
   * visé par le plafond anti-abus (un commerçant qui gonfle artificiellement
   * son propre classement) ne s'applique pas de la même façon. Le plafond de
   * 5 promos *actives* (`assertUnderCap`) reste lui appliqué à tout le
   * monde : ce n'est pas une mesure anti-abus mais une règle métier
   * structurelle sur le volume par commerçant.
   */
  async create(
    commercantId: string,
    dto: CreatePromoDto,
    options?: { trustedActor?: boolean; actorId?: string },
  ): Promise<Promo> {
    const commercant =
      await this.commercantService.findByIdOrFail(commercantId);
    this.commercantService.assertAccountActive(commercant);
    // Les deux gardes de publication ne s'appliquent qu'à la branche qui
    // publie. Posées ici pour tout le monde, elles refusaient aussi
    // « Enregistrer comme brouillon » — avec un message parlant de publier,
    // sur un geste qui ne publie pas : un commerçant dont le profil est en
    // relecture ne pouvait plus rien préparer en attendant (revue
    // 2026-08-05). `publish` les rappelle de toute façon.
    if (!dto.asDraft) {
      this.commercantService.assertRegistreValidated(commercant);
      this.commercantService.assertProfileValidated(commercant);
    }
    this.assertPriceOrder(dto.prixAvant, dto.prixApres);
    this.assertPhotoKeysOwned(dto.photoKeys, commercantId, options?.actorId);
    const thumbnailKey = await this.tryGenerateThumbnail(dto.photoKeys[0]);

    const base = {
      commercantId,
      description: dto.description,
      prixAvant: dto.prixAvant.toFixed(2),
      prixApres: dto.prixApres.toFixed(2),
      categorie: dto.categorie,
      photoKeys: dto.photoKeys,
      thumbnailKey,
    };

    if (dto.asDraft) {
      return this.withCommercantLock(commercantId, async (manager) => {
        if (!options?.trustedActor) {
          await this.assertUnderDailyCreationCap(manager, commercantId);
        }
        return manager.save(
          manager.create(Promo, {
            ...base,
            dateFin: null,
            lifecycleStatus: PromoLifecycleStatus.BROUILLON,
          }),
        );
      });
    }

    const dateFin = this.resolveDateFin(dto.dateFin, dto.dureeJours);
    return this.withCommercantLock(commercantId, async (manager) => {
      await this.assertUnderCap(manager, commercantId);
      if (!options?.trustedActor) {
        await this.assertUnderDailyCreationCap(manager, commercantId);
      }
      return manager.save(
        manager.create(Promo, {
          ...base,
          dateFin,
          lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
          publishedAt: new Date(),
        }),
      );
    });
  }

  /**
   * Publie un brouillon, ou republie une promo arrêtée/expirée — toujours
   * avec une `dateFin` recalculée à neuf (jamais une simple prolongation :
   * specs §3.2, "republication complète requise pour réactiver"). C'est ce
   * geste explicite qui constitue la republication complète, pas une
   * resaisie du formulaire. Une republication est soumise à un cooldown
   * anti-abus (voir `assertRepublishCooldown`) — sans quoi un cycle
   * arrêt→republication répété permettrait de garder artificiellement la
   * promo en tête du tri "plus récentes en premier" côté client.
   * `trustedActor` : même exemption que `create` ci-dessus, pour l'agent
   * qui republie pour le compte d'un commerçant.
   */
  async publish(
    promoId: string,
    options?: { trustedActor?: boolean },
  ): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    if (this.isEnLigne(promo)) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_ALREADY_PUBLISHED,
        'Cette promo est déjà publiée',
      );
    }
    if (!options?.trustedActor) {
      this.assertRepublishCooldown(promo);
    }
    const commercant = await this.commercantService.findByIdOrFail(
      promo.commercantId,
    );
    this.commercantService.assertAccountActive(commercant);
    this.commercantService.assertRegistreValidated(commercant);
    this.commercantService.assertProfileValidated(commercant);

    const dateFin = this.resolveDateFin();
    return this.withCommercantLock(promo.commercantId, async (manager) => {
      await this.assertUnderCap(manager, promo.commercantId);
      promo.lifecycleStatus = PromoLifecycleStatus.PUBLIEE;
      promo.dateFin = dateFin;
      promo.publishedAt = new Date();
      return manager.save(promo);
    });
  }

  /** Arrêt volontaire par le commerçant (ex. rupture de stock) — libère un slot immédiatement. */
  async stop(promoId: string): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    if (promo.lifecycleStatus !== PromoLifecycleStatus.PUBLIEE) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_NOT_PUBLISHED,
        'Seule une promo publiée peut être arrêtée',
      );
    }
    promo.lifecycleStatus = PromoLifecycleStatus.ARRETEE;
    return this.promos.save(promo);
  }

  /**
   * Liste des promos actives filtrée par commune/catégorie (specs §3.1).
   * Tri par défaut : favoris d'abord, puis plus récemment publiées en
   * premier (retour terrain 2026-07-14 — remplace l'ancien tri par
   * expiration la plus proche, toujours disponible côté client comme option
   * de tri manuelle).
   */
  async findActiveForClient(
    query: ListPromoQueryDto,
  ): Promise<PaginatedResult<Promo>> {
    // Les cinq conditions de visibilité viennent de `applyVisibleConditions`
    // et de nulle part ailleurs — dont les gardes commerçant, défensives en
    // plus de la cascade posée par `CommercantService` (suspend/delete
    // repassent déjà les promos en BROUILLON/SUPPRIMEE), pour ne jamais
    // dépendre uniquement de cette cascade ayant réussi.
    const qb = this.applyVisibleConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoinAndSelect('promo.commercant', 'commercant'),
    );

    if (query.communeIds?.length) {
      qb.andWhere('commercant.communeId IN (:...communeIds)', {
        communeIds: query.communeIds,
      });
    }
    if (query.categorie) {
      qb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }
    if (query.commercantId) {
      qb.andWhere('promo.commercantId = :commercantId', {
        commercantId: query.commercantId,
      });
    }
    if (query.search) {
      // Même formulation que la recherche admin (`findAllForAdmin`) : la
      // description de la promo ou le nom du commerce. Non indexé (ILIKE
      // '%…%'), acceptable au volume du pilote — à revoir en trigrammes
      // (pg_trgm) avant l'extension multi-wilaya.
      qb.andWhere(
        '(promo.description ILIKE :search OR commercant.nom ILIKE :search)',
        { search: `%${query.search}%` },
      );
    }

    // Tri "meilleures réductions" (bandeau Top promos de l'accueil) : la
    // remise est recalculée en SQL, aucune colonne dérivée n'existe. Le
    // garde-fou sur `prixAvant > 0` évite une division par zéro sur une
    // ligne aberrante.
    if (query.sort === PromoSortOrder.DISCOUNT) {
      qb.addSelect(
        `CASE WHEN promo."prixAvant" > 0
              THEN (promo."prixAvant" - promo."prixApres") / promo."prixAvant"
              ELSE 0 END`,
        'discount_ratio',
      ).orderBy('discount_ratio', 'DESC');
      qb.addOrderBy('promo.publishedAt', 'DESC', 'NULLS LAST');
      qb.skip((query.page - 1) * query.limit).take(query.limit);
      const [items, total] = await qb.getManyAndCount();
      return toPaginatedResult(items, total, query.page, query.limit);
    }

    if (query.favoriteIds?.length) {
      // Favori par promo (id de la promo elle-même), pas par commerçant —
      // décision produit du 2026-07-12 confirmant ce comportement après une
      // régression : une session précédente avait aligné ceci sur
      // commercantId en lisant "Favoris commerçant" dans les specs §3.1,
      // qui reste à corriger dans le même sens.
      qb.addSelect(
        `CASE WHEN promo.id IN (:...favoriteIds) THEN 0 ELSE 1 END`,
        'favorite_rank',
      ).setParameter('favoriteIds', query.favoriteIds);
      qb.orderBy('favorite_rank', 'ASC');
    }
    // NULLS LAST : toutes les promos ici sont PUBLIEE donc publishedAt est
    // normalement toujours renseigné, mais une ligne pré-migration mal
    // backfillée ne doit pas remonter en tête d'un tri DESC (comportement
    // par défaut de Postgres pour NULL en DESC).
    qb.addOrderBy('promo.publishedAt', 'DESC', 'NULLS LAST');
    qb.skip((query.page - 1) * query.limit).take(query.limit);

    const [items, total] = await qb.getManyAndCount();
    return toPaginatedResult(items, total, query.page, query.limit);
  }

  /**
   * Commerçants géolocalisés de la zone visible, avec leurs promos actives
   * (écran carte "autour de moi"). Volontairement dans `PromoService` et non
   * dans `CommercantService` : la définition de "promo visible" vit ici et
   * ne doit pas être réécrite ailleurs (règle d'audit #9, deux services
   * ayant déjà divergé sur cette règle par le passé).
   *
   * Deux requêtes fixes, jamais une par commerçant (règle d'audit #14) : la
   * première sélectionne les commerçants de la zone ayant au moins une promo
   * visible, la seconde charge leurs promos d'un coup.
   */
  async findActiveForMap(query: ListPromoMapQueryDto): Promise<{
    commercants: { commercant: Commercant; promos: Promo[] }[];
    truncated: boolean;
  }> {
    const visiblePromoConditions = (qb: SelectQueryBuilder<Promo>) =>
      qb
        .where('promo.lifecycleStatus = :lifecycleStatus', {
          lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        })
        .andWhere('promo.moderationStatus IN (:...moderationStatuses)', {
          moderationStatuses: VISIBLE_MODERATION_STATUSES,
        })
        .andWhere('promo.dateFin > NOW()')
        .andWhere('commercant.deletedAt IS NULL')
        .andWhere('commercant.suspendedAt IS NULL');

    const commercantsQb = visiblePromoConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoin('promo.commercant', 'commercant'),
    )
      .andWhere('commercant.latitude IS NOT NULL')
      .andWhere('commercant.longitude IS NOT NULL')
      .andWhere('commercant.latitude BETWEEN :south AND :north', {
        south: query.south,
        north: query.north,
      })
      .andWhere('commercant.longitude BETWEEN :west AND :east', {
        west: query.west,
        east: query.east,
      })
      .select('commercant.id', 'id')
      .distinct(true)
      // +1 pour détecter le dépassement sans seconde requête de comptage.
      .limit(MAX_MAP_COMMERCANTS + 1);

    if (query.categorie) {
      commercantsQb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }

    const rows = await commercantsQb.getRawMany<{ id: string }>();
    const truncated = rows.length > MAX_MAP_COMMERCANTS;
    const commercantIds = rows
      .slice(0, MAX_MAP_COMMERCANTS)
      .map((row) => row.id);
    if (commercantIds.length === 0)
      return { commercants: [], truncated: false };

    const promosQb = visiblePromoConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoinAndSelect('promo.commercant', 'commercant'),
    )
      .andWhere('promo.commercantId IN (:...commercantIds)', { commercantIds })
      .addOrderBy('promo.publishedAt', 'DESC', 'NULLS LAST');

    if (query.categorie) {
      promosQb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }

    const promos = await promosQb.getMany();

    const grouped = new Map<
      string,
      { commercant: Commercant; promos: Promo[] }
    >();
    for (const promo of promos) {
      const entry = grouped.get(promo.commercantId);
      if (entry) {
        entry.promos.push(promo);
      } else {
        grouped.set(promo.commercantId, {
          commercant: promo.commercant,
          promos: [promo],
        });
      }
    }

    return { commercants: [...grouped.values()], truncated };
  }

  /**
   * Vue admin/agent (plan de correction, Phase 2) : toutes les promos, tous
   * statuts confondus (contrairement à `findActiveForClient`) — permet de
   * repérer et masquer un contenu problématique sans attendre 3
   * signalements. `scopedCommuneIds` restreint aux communes d'un agent ;
   * `undefined` = vue globale (admin).
   */
  async findAllForAdmin(
    query: ListPromoAdminQueryDto,
    scopedCommuneIds?: string[],
  ): Promise<PaginatedResult<Promo>> {
    if (scopedCommuneIds && scopedCommuneIds.length === 0) {
      return toPaginatedResult([], 0, query.page, query.limit);
    }

    const qb = this.promos
      .createQueryBuilder('promo')
      .innerJoinAndSelect('promo.commercant', 'commercant')
      .orderBy('promo.createdAt', 'DESC');

    if (query.search) {
      qb.andWhere(
        '(promo.description ILIKE :search OR commercant.nom ILIKE :search)',
        { search: `%${query.search}%` },
      );
    }
    if (query.communeId) {
      qb.andWhere('commercant.communeId = :communeId', {
        communeId: query.communeId,
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
    if (query.categorie) {
      qb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }
    if (query.lifecycleStatus) {
      qb.andWhere('promo.lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: query.lifecycleStatus,
      });
    }
    if (query.moderationStatus) {
      qb.andWhere('promo.moderationStatus = :moderationStatus', {
        moderationStatus: query.moderationStatus,
      });
    }
    if (scopedCommuneIds) {
      qb.andWhere('commercant.communeId IN (:...scopedCommuneIds)', {
        scopedCommuneIds,
      });
    }
    qb.skip((query.page - 1) * query.limit).take(query.limit);

    const [items, total] = await qb.getManyAndCount();
    return toPaginatedResult(items, total, query.page, query.limit);
  }

  async findByIdOrFail(id: string): Promise<Promo> {
    const promo = await this.promos.findOne({
      where: { id },
      relations: { commercant: true },
    });
    if (!promo) {
      throw new NotFoundAppException(
        ErrorCode.PROMO_NOT_FOUND,
        'Promo introuvable',
      );
    }
    return promo;
  }

  /**
   * Une seule requête pour plusieurs ids (ex. file de modération) — jamais
   * `ids.map(id => findByIdOrFail(id))`, qui refait un SELECT par élément
   * (CLAUDE.md règle #14, N+1 réapparu sur ce même écran après le premier
   * correctif V0, cf. audit V1 §5).
   */
  async findByIds(ids: string[]): Promise<Promo[]> {
    if (ids.length === 0) return [];
    return this.promos.find({
      where: { id: In(ids) },
      relations: { commercant: true },
    });
  }

  /**
   * Sous-ensemble de [ids] réellement visible par un client — même règle que
   * `findActiveForClient` (publiée, modération non bloquante, non expirée,
   * commerçant ni supprimé ni suspendu), appliquée ici plutôt que réécrite
   * par l'appelant (CLAUDE.md règle #9 : la définition de « promo visible »
   * ne vit qu'ici).
   *
   * Utilisé par le bandeau d'accueil curé (`HighlightService`) : une
   * diapositive pointant vers une promo devenue invisible doit disparaître,
   * pas afficher un lien mort.
   */
  async findVisibleByIds(ids: string[]): Promise<Promo[]> {
    if (ids.length === 0) return [];
    return this.applyVisibleConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoinAndSelect('promo.commercant', 'commercant')
        .where('promo.id IN (:...ids)', { ids }),
    ).getMany();
  }

  /**
   * Variante unitaire pour la route publique de lien partagé (`/p/:id`) —
   * `findByIdOrFail` ne filtre par construction aucun statut (les flux
   * commerçant/agent doivent atteindre leurs propres promos quel qu'il soit),
   * et le contrôleur n'en réappliquait qu'une condition sur cinq : une promo
   * arrêtée, expirée, en brouillon, ou d'un commerçant suspendu restait
   * intégralement consultable par quiconque avait le lien — une offre périmée
   * se présentant comme en cours, une suspension ne coupant pas les liens
   * déjà en circulation (revue 2026-08-05).
   */
  async findVisibleByIdOrFail(id: string): Promise<Promo> {
    const [promo] = await this.findVisibleByIds([id]);
    if (!promo) {
      throw new NotFoundAppException(
        ErrorCode.PROMO_NOT_FOUND,
        'Promo introuvable',
      );
    }
    return promo;
  }

  /**
   * Nombre de promos occupant réellement un emplacement du plafond, et le
   * plafond lui-même — servis à `GET /commercant/me`.
   *
   * L'app le dérivait d'une page de `GET /promo/me/all` limitée à 100, **tous
   * statuts confondus**, en comptant les `publiee`. Deux erreurs : au-delà de
   * 100 promos cumulées le compte devient faux sans rien dire (le tableau de
   * bord annonçait « 2 emplacements restants » pendant que le serveur refusait
   * en `PROMO_ACTIVE_CAP_REACHED`), et une promo expirée mais pas encore
   * basculée par le cron y comptait alors qu'elle n'occupe plus rien
   * (`isEnLigne`). Le plafond voyage aussi, pour que l'app cesse de recopier
   * `5` (revue 2026-08-05, règles #29 et #32).
   */
  async getSlotUsage(
    commercantId: string,
  ): Promise<{ enLigne: number; plafond: number }> {
    const enLigne = await this.promos.count({
      where: {
        commercantId,
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        dateFin: MoreThan(new Date()),
      },
    });
    return { enLigne, plafond: MAX_PROMOS_ACTIVES };
  }

  async listByCommercant(
    commercantId: string,
    page: number,
    limit: number,
  ): Promise<PaginatedResult<Promo>> {
    const [items, total] = await this.promos.findAndCount({
      where: { commercantId },
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  async recordView(promoId: string, deviceId: string): Promise<void> {
    await this.views
      .createQueryBuilder()
      .insert()
      .values({ promoId, deviceId })
      .orIgnore()
      .execute();
  }

  async getViewCounts(promoIds: string[]): Promise<Record<string, number>> {
    if (promoIds.length === 0) return {};
    const rows = await this.views
      .createQueryBuilder('view')
      .select('view.promoId', 'promoId')
      .addSelect('COUNT(*)', 'count')
      .where('view.promoId IN (:...promoIds)', { promoIds })
      .groupBy('view.promoId')
      .getRawMany<{ promoId: string; count: string }>();

    return Object.fromEntries(
      rows.map((row) => [row.promoId, Number(row.count)]),
    );
  }

  /** Tâche planifiée quotidienne (specs §5.1) — bascule automatique à expiration. */
  @Cron(CronExpression.EVERY_DAY_AT_1AM)
  async expireOutdatedPromosCron(): Promise<void> {
    const count = await this.expireOutdatedPromos();
    this.logger.log(`${count} promo(s) passée(s) en statut expirée`);
  }

  async expireOutdatedPromos(): Promise<number> {
    const result = await this.promos
      .createQueryBuilder()
      .update(Promo)
      .set({ lifecycleStatus: PromoLifecycleStatus.EXPIREE })
      .where('dateFin < NOW()')
      .andWhere('lifecycleStatus = :lifecycleStatus', {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
      })
      .execute();
    return result.affected ?? 0;
  }

  /**
   * Relance avant expiration (plan de correction, Phase 6) — jusqu'ici rien
   * ne notifiait le commerçant qu'une promo allait bientôt expirer, tout
   * reposait sur lui pour penser à republier. Fenêtre de 24h alignée sur la
   * cadence quotidienne du cron : chaque promo ne peut croiser cette
   * fenêtre qu'une seule fois (pas de doublon, pas de promo manquée).
   */
  @Cron(CronExpression.EVERY_DAY_AT_9AM)
  async notifyExpiringSoonCron(): Promise<void> {
    // `moderationStatus IN VISIBLE_MODERATION_STATUSES` : une promo masquée
    // par un admin reste `lifecycleStatus = PUBLIEE` en interne (masquer ne
    // touche que moderationStatus) — sans ce filtre, on inviterait le
    // commerçant à "republier" un contenu que l'admin vient justement de
    // retirer pour abus, message contradictoire avec la modération.
    const expiring = await this.promos.find({
      where: {
        lifecycleStatus: PromoLifecycleStatus.PUBLIEE,
        moderationStatus: In(VISIBLE_MODERATION_STATUSES),
        dateFin: Between(
          new Date(),
          new Date(Date.now() + EXPIRING_SOON_WINDOW_HOURS * 60 * 60 * 1000),
        ),
      },
    });

    for (const promo of expiring) {
      await this.notificationService.create(
        NotificationType.PROMO_EXPIRING_SOON,
        NotificationRecipientType.COMMERCANT,
        promo.commercantId,
        `Votre promo « ${promo.description} » expire bientôt. Pensez à la republier.`,
        promo.id,
        // Seul site de notification qui ne passait pas la description en
        // métadonnée : sans elle, l'app ne peut pas composer la phrase
        // localisée et retombe sur le `message` français.
        { promoDescription: promo.description },
      );
    }
    this.logger.log(`${expiring.length} promo(s) notifiée(s) avant expiration`);
  }

  async markSignalee(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId, moderationStatus: Not(PromoModerationStatus.MASQUEE) },
      { moderationStatus: PromoModerationStatus.SIGNALEE },
    );
  }

  /** Décision admin : masquer une promo signalée à tort ou réellement abusive (specs §3.4). */
  async resolveMasquer(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId },
      { moderationStatus: PromoModerationStatus.MASQUEE },
    );
  }

  /** Décision admin : promo légitime — ouvre la fenêtre d'ignore de 30 jours (specs §5.4). */
  async resolveVerifieOk(promoId: string): Promise<void> {
    await this.promos.update(
      { id: promoId },
      {
        moderationStatus: PromoModerationStatus.VERIFIEE_OK,
        verifiedOkAt: new Date(),
      },
    );
  }

  /**
   * Décision admin : avertir le commerçant — repasse la promo en brouillon
   * (donc invisible côté client, `dateFin` remise à null comme tout
   * brouillon) le temps que le commerçant la vérifie et la republie
   * explicitement via `publish` (pas de republication automatique).
   */
  async resolveAvertir(promoId: string): Promise<void> {
    // Le déblocage ne visait que `SIGNALEE`, jamais `MASQUEE` : « avertir »
    // après « masquer » laissait le masque en place tout en notifiant
    // « republiez-la ». Le commerçant republiait, consommait un de ses 5
    // emplacements, obtenait 0 vue, et n'avait aucun moyen de le voir —
    // `moderationStatus` n'est affiché sur aucun écran commerçant (revue
    // 2026-08-05, règle #8). L'avertissement lève donc tout statut bloquant :
    // c'est le retour en brouillon qui porte la sanction, pas le masque.
    await this.promos.update(
      { id: promoId },
      {
        moderationStatus: PromoModerationStatus.NORMALE,
        lifecycleStatus: PromoLifecycleStatus.BROUILLON,
        dateFin: null,
      },
    );
  }

  /**
   * Édition du contenu — autorisée quel que soit le cycle de vie (brouillon,
   * publiée, arrêtée, expirée) : c'est l'action de publication/republication
   * qui constitue le "geste actif" des specs, pas une restriction sur
   * l'édition elle-même.
   */
  async update(
    promoId: string,
    dto: UpdatePromoDto,
    options?: { actorId?: string },
  ): Promise<Promo> {
    const promo = await this.findByIdOrFail(promoId);
    const prixAvant = dto.prixAvant ?? Number(promo.prixAvant);
    const prixApres = dto.prixApres ?? Number(promo.prixApres);
    this.assertPriceOrder(prixAvant, prixApres);
    if (dto.photoKeys) {
      this.assertPhotoKeysOwned(
        dto.photoKeys,
        promo.commercantId,
        options?.actorId,
      );
    }
    const previousPhotoKeys = promo.photoKeys;
    const previousThumbnailKey = promo.thumbnailKey;
    let thumbnailKey = previousThumbnailKey;
    // Régénérée uniquement si la 1ère photo change (pas juste réordonnée à
    // l'identique) — évite un aller-retour S3 (download + resize + upload)
    // inutile à chaque édition de description/prix.
    if (dto.photoKeys && dto.photoKeys[0] !== previousPhotoKeys[0]) {
      thumbnailKey = await this.tryGenerateThumbnail(dto.photoKeys[0]);
    }

    // **UPDATE ciblé, jamais `save(promo)`.** `promo` est un instantané pris
    // AVANT l'aller-retour S3 de `tryGenerateThumbnail` (plusieurs secondes
    // sur une connexion lente) ; un `save` de l'entité complète réécrit
    // toutes ses colonnes depuis cet instantané périmé, dont
    // `moderationStatus` et `lifecycleStatus`. Une décision de modération
    // prise pendant cette fenêtre — « masquer » sur une promo signalée —
    // était donc annulée par l'édition, sans erreur, l'admin croyant la
    // promo masquée (revue 2026-08-05, règle #13). N'écrire que les colonnes
    // de contenu laisse la modération et le cycle de vie à leurs
    // propriétaires (`resolveMasquer`, `publish`, `stop`, le cron).
    //
    // `dto` porte une propriété propre `undefined` pour chaque champ
    // optionnel non fourni (`useDefineForClassFields`) — d'où le filtrage,
    // sans quoi TypeORM recevrait des `undefined` et l'objet renvoyé au
    // client perdrait `description`/`categorie` lors d'un simple changement
    // de photo (même bug que `CommercantService.updateProfile`, 2026-07-12).
    const contentFields = Object.fromEntries(
      Object.entries({
        description: dto.description,
        categorie: dto.categorie,
        photoKeys: dto.photoKeys,
        prixAvant: dto.prixAvant?.toFixed(2),
        prixApres: dto.prixApres?.toFixed(2),
        thumbnailKey:
          thumbnailKey === previousThumbnailKey ? undefined : thumbnailKey,
      }).filter(([, value]) => value !== undefined),
    );
    if (Object.keys(contentFields).length > 0) {
      await this.promos.update({ id: promoId }, contentFields);
    }
    // Relecture plutôt que l'instantané modifié : la réponse doit porter le
    // `moderationStatus`/`lifecycleStatus` réel, y compris s'il a changé
    // pendant l'édition.
    const saved = await this.findByIdOrFail(promoId);
    // Le mobile envoie toujours le tableau complet résolu (clés inchangées
    // réutilisées telles quelles, voir `PromoFormScreen`) — une clé absente
    // du nouveau tableau a donc été explicitement retirée ou remplacée, et
    // devient orpheline dans S3 si on ne la supprime pas ici (`buildKey`
    // génère toujours une nouvelle clé UUID, jamais un remplacement en place).
    if (dto.photoKeys) {
      const removedKeys = previousPhotoKeys.filter(
        (key) => !dto.photoKeys!.includes(key),
      );
      for (const key of removedKeys) {
        await this.storageService.deleteObject(key);
      }
    }
    if (previousThumbnailKey && previousThumbnailKey !== thumbnailKey) {
      await this.storageService.deleteObject(previousThumbnailKey);
    }
    return saved;
  }

  /** Une promo est censée être une réduction — le prix après doit être strictement inférieur. */
  private assertPriceOrder(prixAvant: number, prixApres: number): void {
    if (prixApres >= prixAvant) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_PRIX_APRES_NOT_LOWER,
        'Le prix après réduction doit être inférieur au prix avant réduction',
      );
    }
  }

  /**
   * Tâche planifiée indépendante du cron d'expiration fonctionnelle (specs
   * §5.8) : supprime le fichier S3 des promos de plus d'un mois, mais
   * conserve les métadonnées en base indéfiniment (historique dashboard).
   */
  @Cron(CronExpression.EVERY_DAY_AT_2AM)
  async purgeOldPhotosCron(): Promise<void> {
    const cutoff = new Date(
      Date.now() - this.imageRetentionDays() * 24 * 60 * 60 * 1000,
    );
    const eligible = await this.promos.find({
      where: { photoPurgedAt: IsNull(), createdAt: LessThan(cutoff) },
    });

    for (const promo of eligible) {
      for (const key of promo.photoKeys) {
        await this.storageService.deleteObject(key);
      }
      if (promo.thumbnailKey) {
        await this.storageService.deleteObject(promo.thumbnailKey);
      }
      promo.photoPurgedAt = new Date();
      await this.promos.save(promo);
    }

    this.logger.log(
      `${eligible.length} photo(s) de promo purgée(s) du stockage S3`,
    );
  }

  /**
   * Utilisé par le dashboard admin/agent (partagé, décision produit
   * 2026-07-12). Filtre aussi sur `dateFin` comme `findActiveForClient` —
   * sans ça, une promo expirée reste comptée comme "publiée" jusqu'au
   * passage du cron quotidien (`expireOutdatedPromosCron`), jusqu'à 24h de
   * statistique fausse. `communeIds` restreint aux communes d'un agent —
   * `undefined` = vue globale (admin).
   */
  async countVisible(communeIds?: string[]): Promise<number> {
    if (communeIds && communeIds.length === 0) return 0;

    // La jointure sur `commercant` est désormais inconditionnelle : elle ne
    // servait qu'au filtre par commune, si bien que la vue admin (sans
    // `communeIds`) comptait les promos de comptes supprimés ou suspendus —
    // le dashboard annonçait des promos publiées qu'aucun client ne voyait.
    const qb = this.applyVisibleConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoin('promo.commercant', 'commercant'),
    );

    if (communeIds) {
      qb.andWhere('commercant.communeId IN (:...communeIds)', { communeIds });
    }
    return qb.getCount();
  }
}

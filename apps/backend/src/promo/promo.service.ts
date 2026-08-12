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
  ObjectLiteral,
  Repository,
  SelectQueryBuilder,
} from 'typeorm';
import { CommercantService } from '../commercant/commercant.service';
import { Commercant } from '../commercant/entities/commercant.entity';
import { withTimeout } from '../common/async/with-timeout';
import { configNumber } from '../common/config/config-number';
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

/**
 * ⚠️ **Le plafond n'est plus une constante** (2026-08-05). Il était le seul de
 * la famille à exiger un redéploiement pour bouger, alors que ses quatre
 * voisines immédiates — durée par défaut, durée maximale, plafond quotidien,
 * cooldown de republication — se règlent toutes par variable d'environnement.
 * Voir `plafondActif()`, et `PROMO_ACTIVE_CAP` dans `.env.example`.
 * Depuis le 2026-08-05, un commerçant peut porter le sien
 * (`Commercant.promoActiveCap`) ; `null` suit le global.
 *
 * Il n'est **pas** recopié côté app : `GET /promo/me/slots` le sert avec le
 * décompte (`getSlotUsage`), de sorte qu'un changement de plafond ne demande
 * aucune recompilation mobile.
 */

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
 *
 * ⚠️ **Ce n'est plus une constante, c'est un repli** : la valeur effective est
 * lue par `maxMapCommercants()` depuis `MAX_MAP_COMMERCANTS` (`.env`).
 *
 * Elle n'est **pas** servie à l'app, et c'est délibéré : `client_carte.py` la
 * **déduit** de la réponse (`truncated` + taille de la liste) au lieu de la
 * recopier, ce qui permet de la changer sans toucher au banc (règle #32).
 */
const DEFAUT_MAX_MAP_COMMERCANTS = 300;

/**
 * Repères géographiques servis au client (`GET /promo/config`).
 *
 * ── Pourquoi ces valeurs vivent dans le `.env` du serveur ─────────────────
 *
 * Parce que le mobile n'a pas de `.env` : `lib/config/env.dart` n'expose que
 * des `String.fromEnvironment`, compilés dans le binaire — et `CLAUDE.md`
 * documente qu'un `--dart-define` **se perd silencieusement** selon la façon
 * dont `flutter` est lancé. Une valeur compilée ne se change qu'en republiant
 * sur les deux stores.
 *
 * Le cas concret qui l'impose : le défaut est **Alger** et le pilote est à
 * **Djelfa**. Un rayon de 5 km autour d'Alger rend la liste vide pour tout
 * client du pilote qui n'a pas enregistré son point. C'est une ligne de `.env`
 * à changer, pas une soumission au store.
 *
 * ⚠️ Ces quatre-là sont des **replis journalisés**, pas la valeur servie :
 * `getClientConfig()` lit la configuration à chaque appel (même contrat que
 * `plafondActif` pour `PROMO_ACTIVE_CAP`).
 */
const DEFAUT_CLIENT_LATITUDE = 36.7538; // Alger
const DEFAUT_CLIENT_LONGITUDE = 3.0588; // Alger
const DEFAUT_CLIENT_RADIUS_KM = 5;

/**
 * Plafond du rayon acceptable sur `GET /promo`.
 *
 * ⚠️ **Ce n'est pas un confort, c'est une borne de sécurité** : le rayon
 * dérive une bbox sur une route **publique et non authentifiée**. Sans
 * plafond, `?radiusKm=100000` demande un parcours complet de la table à
 * volonté (règle #34, second temps : « un DTO décoré n'est pas un DTO
 * borné »). 50 km couvre une agglomération et sa périphérie ; au-delà, c'est
 * la recherche textuelle qui prend le relais, elle qui ignore le rayon.
 */
const DEFAUT_CLIENT_MAX_RADIUS_KM = 50;

/**
 * Délai au-delà duquel on renonce à la miniature (P9). Mesuré : une génération
 * saine prend **88 ms** contre MinIO en local, en incluant le
 * téléchargement de l'original et le réencodage. Cinq secondes laissent donc
 * une marge de deux ordres de grandeur — c'est un filet contre un stockage
 * injoignable, pas un budget de performance à respecter au plus juste.
 */
const THUMBNAIL_TIMEOUT_MS = 5_000;

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

  /**
   * ⚠️ Toutes les lectures numériques passent par `configNumber`, jamais par
   * `get<number>` : cette annotation ne convertit rien, et une variable
   * définie dans `.env` arrive donc en **chaîne**. Inoffensif tant que l'usage
   * est arithmétique (JavaScript coerce), fatal dès que la valeur sort en JSON
   * — voir `configNumber` et son banc.
   */
  private defaultDureeJours(): number {
    return configNumber(
      this.configService.get('PROMO_DEFAULT_DURATION_DAYS'),
      5,
      'PROMO_DEFAULT_DURATION_DAYS',
    );
  }

  private maxDureeJours(): number {
    return configNumber(
      this.configService.get('PROMO_MAX_DURATION_DAYS'),
      7,
      'PROMO_MAX_DURATION_DAYS',
    );
  }

  private imageRetentionDays(): number {
    return configNumber(
      this.configService.get('IMAGE_RETENTION_DAYS'),
      30,
      'IMAGE_RETENTION_DAYS',
    );
  }

  /** Anti-abus (retour terrain 2026-07-14) — voir `assertUnderDailyCreationCap`. */
  private dailyCreationCap(): number {
    return configNumber(
      this.configService.get('PROMO_DAILY_CREATION_CAP'),
      5,
      'PROMO_DAILY_CREATION_CAP',
    );
  }

  /** Anti-abus (retour terrain 2026-07-14) — voir `assertRepublishCooldown`. */
  private republishCooldownHours(): number {
    return configNumber(
      this.configService.get('PROMO_REPUBLISH_COOLDOWN_HOURS'),
      24,
      'PROMO_REPUBLISH_COOLDOWN_HOURS',
    );
  }

  /**
   * Nombre de promos simultanément en ligne autorisées par commerçant
   * (specs §3.2). Servi tel quel à l'app par `getSlotUsage` — c'est cette
   * valeur, et non une copie compilée, qui remplit le compteur d'emplacements.
   */
  private plafondParDefaut(): number {
    return configNumber(
      this.configService.get('PROMO_ACTIVE_CAP'),
      5,
      'PROMO_ACTIVE_CAP',
    );
  }

  /** Voir `DEFAUT_MAX_MAP_COMMERCANTS` — non servi à l'app, déduit de la réponse. */
  private maxMapCommercants(): number {
    return configNumber(
      this.configService.get('MAX_MAP_COMMERCANTS'),
      DEFAUT_MAX_MAP_COMMERCANTS,
      'MAX_MAP_COMMERCANTS',
      { minimum: 1 },
    );
  }

  /**
   * Repères géographiques servis à l'app (`GET /promo/config`).
   *
   * ⚠️ **C'est cette réponse, et non une copie compilée, qui fait foi côté
   * app** — même contrat que `plafond` dans `getSlotUsage`. Recopier l'une de
   * ces valeurs dans le mobile la ferait diverger au premier changement de
   * `.env`, et `check_server_rules.dart` ne saurait même pas le voir : ses
   * regex capturent `(\d+)` et font `int.parse`, donc `36.7538` y serait lu
   * `36` **en rendant vert** (revue 2026-08-12, règle #32).
   *
   * ⚠️ Les latitudes et longitudes passent un intervalle **signé** :
   * `{ minimum: -180 }` est ce qui lève le refus de zéro et du négatif dans
   * `configNumber`. Sans lui, toute longitude ouest — Oran, Tlemcen, Sidi Bel
   * Abbès — retomberait sur le repli, en silence pour qui ne lit pas les
   * journaux.
   */
  getClientConfig(): {
    defaultLatitude: number;
    defaultLongitude: number;
    defaultRadiusKm: number;
    maxRadiusKm: number;
  } {
    return {
      defaultLatitude: configNumber(
        this.configService.get('CLIENT_DEFAULT_LATITUDE'),
        DEFAUT_CLIENT_LATITUDE,
        'CLIENT_DEFAULT_LATITUDE',
        { minimum: -90, maximum: 90 },
      ),
      defaultLongitude: configNumber(
        this.configService.get('CLIENT_DEFAULT_LONGITUDE'),
        DEFAUT_CLIENT_LONGITUDE,
        'CLIENT_DEFAULT_LONGITUDE',
        { minimum: -180, maximum: 180 },
      ),
      defaultRadiusKm: configNumber(
        this.configService.get('CLIENT_DEFAULT_RADIUS_KM'),
        DEFAUT_CLIENT_RADIUS_KM,
        'CLIENT_DEFAULT_RADIUS_KM',
        { minimum: 1 },
      ),
      maxRadiusKm: configNumber(
        this.configService.get('CLIENT_MAX_RADIUS_KM'),
        DEFAUT_CLIENT_MAX_RADIUS_KM,
        'CLIENT_MAX_RADIUS_KM',
        { minimum: 1 },
      ),
    };
  }

  /**
   * **L'unique endroit où se lit « propre au commerçant, sinon global ».**
   *
   * ⚠️ La garde à la création (`assertUnderCap`) et le décompte servi à
   * l'écran (`getSlotUsage`) passent tous deux par ici. Les séparer ferait
   * voir « 3 / 8 » à un commerçant refusé à sa quatrième promo — deux endroits
   * qui répondent à la même question finissent toujours par diverger
   * (règle #30).
   *
   * `null` n'est pas zéro : il dit « suit le défaut ». D'où `??` et non `||`,
   * qui prendrait aussi le défaut pour un plafond de 0 posé volontairement —
   * un commerçant qu'on veut empêcher de publier sans le suspendre.
   */
  private plafondActif(plafondPropre: number | null | undefined): number {
    return plafondPropre ?? this.plafondParDefaut();
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
   * Cadre rectangulaire sur la position du commerçant.
   *
   * **Une seule définition, deux appelants** : la carte (`findActiveForMap`) et
   * la liste au rayon (`findActiveForClient`). Le critère de la règle #30 est
   * « si l'un change, l'autre doit-il changer ? » — ici oui, c'est la même
   * question posée deux fois, et un commentaire « même filtre que la carte »
   * n'aurait rien tenu.
   *
   * ⚠️ C'est ce `BETWEEN`, et lui seul, qui emprunte `IDX_commercant_position`
   * (btree partiel sur `latitude, longitude`). L'ordre par distance, lui,
   * porte sur une expression calculée et ne peut pas être servi par un btree :
   * le cadre est donc ce qui rend le tri abordable, pas un raffinement.
   *
   * Exige que `commercant` soit déjà joint sous cet alias.
   */
  private applyBoundingBox<T extends ObjectLiteral>(
    qb: SelectQueryBuilder<T>,
    bornes: { north: number; south: number; east: number; west: number },
  ): SelectQueryBuilder<T> {
    return qb
      .andWhere('commercant.latitude BETWEEN :bboxSouth AND :bboxNorth', {
        bboxSouth: bornes.south,
        bboxNorth: bornes.north,
      })
      .andWhere('commercant.longitude BETWEEN :bboxWest AND :bboxEast', {
        bboxWest: bornes.west,
        bboxEast: bornes.east,
      });
  }

  /**
   * Cadre englobant un rayon, en degrés.
   *
   * 111.32 km par degré de latitude ; en longitude, ce même degré rétrécit
   * avec le cosinus de la latitude. À Djelfa (34.7°) un degré de longitude ne
   * vaut plus que ~91 km : dériver le cadre sans ce cosinus donnerait une
   * boîte trop étroite d'est en ouest, qui **exclurait des commerces réellement
   * dans le rayon** — un manque, jamais un excès, donc invisible à l'usage.
   *
   * Le cadre est volontairement **plus large que le cercle** (ses coins en
   * dépassent). C'est le tri fin par distance qui rogne ces coins, §9.2 du
   * plan : un banc doit éprouver un point dans le carré et hors du cercle,
   * sinon une implémentation qui oublie le rognage rend vert.
   */
  private cadreAutour(
    latitude: number,
    longitude: number,
    rayonKm: number,
  ): { north: number; south: number; east: number; west: number } {
    const deltaLat = rayonKm / 111.32;
    // Aux pôles le cosinus tend vers 0 et le delta exploserait ; on borne le
    // cadre au globe plutôt que de produire des bornes infinies.
    const cosLat = Math.max(Math.cos((latitude * Math.PI) / 180), 0.01);
    const deltaLon = rayonKm / (111.32 * cosLat);
    return {
      north: Math.min(latitude + deltaLat, 90),
      south: Math.max(latitude - deltaLat, -90),
      east: Math.min(longitude + deltaLon, 180),
      west: Math.max(longitude - deltaLon, -180),
    };
  }

  /**
   * Distance à vol d'oiseau en kilomètres, en SQL (haversine).
   *
   * ⚠️ Le `LEAST(1, GREATEST(-1, …))` n'est pas décoratif : l'argument d'`acos`
   * doit rester dans [-1, 1], et l'arithmétique flottante le fait déborder
   * d'un epsilon quand le commerçant est **exactement** sur le point de
   * référence. Sans la borne, Postgres lève `input is out of range` — donc un
   * 500 sur le cas le plus banal qui soit : le client cherche depuis
   * l'intérieur du commerce.
   */
  private readonly distanceKmSql = `(6371 * acos(LEAST(1, GREATEST(-1,
      sin(radians(:refLat)) * sin(radians(commercant.latitude))
      + cos(radians(:refLat)) * cos(radians(commercant.latitude))
        * cos(radians(commercant.longitude) - radians(:refLng))
    ))))`;

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
    // ⚠️ Lu par le `manager`, donc dans la transaction qui porte déjà le
    // verrou consultatif : le plafond ne peut pas changer entre le décompte
    // et la décision.
    const commercant = await manager.findOne(Commercant, {
      where: { id: commercantId },
      select: { id: true, promoActiveCap: true },
    });
    const plafond = this.plafondActif(commercant?.promoActiveCap);

    if (activeCount >= plafond) {
      throw new BadRequestAppException(
        ErrorCode.PROMO_ACTIVE_CAP_REACHED,
        `Plafond de ${plafond} promos actives atteint pour ce commerçant`,
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
      // ⚠️ **Borné, sinon « best-effort » ne veut rien dire.** Cette génération
      // est facultative — la promo se crée sans elle — mais elle vit DANS le
      // chemin de création : son attente est celle de l'utilisateur. Le
      // 2026-08-04, un `S3_ENDPOINT` injoignable depuis le serveur a fait durer
      // une création **plus de 300 secondes** (P9) : le SDK AWS n'impose pas de
      // délai court, et le `catch` ci-dessous attrapait l'échec sans jamais
      // borner l'attente.
      //
      // Le délai est posé ICI et non sur le `S3Client` : un upload légitime de
      // 500 Ko peut dépasser 5 s sans que ce soit une panne. Seul l'accessoire
      // est borné.
      return await withTimeout(
        this.storageService.generateThumbnail(sourceKey),
        THUMBNAIL_TIMEOUT_MS,
        `miniature de ${sourceKey}`,
      );
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

    // ── Périmètre géographique (bascule 2026-08-12) ────────────────────────
    //
    // ⚠️ Le rayon est centré sur **un point**, jamais sur une ville : aucun
    // centroïde de commune n'intervient nulle part ici. Le point vient du
    // client (celui qu'il a enregistré) ou, à défaut, de la configuration
    // serveur.
    //
    // ⚠️ **Et le défaut ne s'applique QUE si la requête ne porte aucun autre
    // périmètre.** Sans cette exception, l'app déjà installée — qui envoie les
    // `communeIds` de Djelfa et aucune position — verrait ses communes croisées
    // avec un rayon autour du point par défaut et n'afficherait plus rien. Même
    // raison pour `commercantId` : « autres promos du magasin » interroge une
    // fiche précise, pas un voisinage (§5.6 du plan).
    const perimetreExplicite =
      Boolean(query.commercantId) || Boolean(query.communeIds?.length);

    const config = this.getClientConfig();

    if (query.radiusKm !== undefined && query.radiusKm > config.maxRadiusKm) {
      // Refus, jamais un rabotage silencieux : l'app lit `maxRadiusKm` sur
      // `GET /promo/config` et n'a aucune raison de dépasser. Une requête qui
      // dépasse est soit un client cassé, soit un abus — dans les deux cas
      // c'est une information, pas quelque chose à corriger en douce
      // (règle #29).
      throw new BadRequestAppException(
        ErrorCode.VALIDATION_ERROR,
        `Rayon de recherche trop grand (${query.radiusKm} km) — maximum ${config.maxRadiusKm} km`,
      );
    }

    const position =
      query.latitude !== undefined && query.longitude !== undefined
        ? { latitude: query.latitude, longitude: query.longitude }
        : perimetreExplicite
          ? null
          : {
              latitude: config.defaultLatitude,
              longitude: config.defaultLongitude,
            };

    // Une recherche textuelle **ignore le rayon** : chercher est un acte
    // intentionnel avec une cible, et la borner au voisinage rendrait le
    // produit structurellement moins capable qu'avant la bascule (le client
    // suivait jusqu'à 4 communes). Le tri par distance reste actif, donc le
    // proche remonte quand même en tête (R8 du plan).
    const rayonKm = query.search
      ? null
      : (query.radiusKm ?? config.defaultRadiusKm);

    if (position) {
      qb.setParameters({
        refLat: position.latitude,
        refLng: position.longitude,
      });
    }

    if (position && rayonKm !== null) {
      // Le cadre d'abord (il emprunte l'index), la distance ensuite (elle
      // rogne les coins du carré). L'ordre des deux conditions n'a pas
      // d'importance pour Postgres, mais leur présence conjointe si : le
      // cadre seul rendrait des commerces jusqu'à 41 % trop loin en diagonale.
      this.applyBoundingBox(
        qb,
        this.cadreAutour(position.latitude, position.longitude, rayonKm),
      );
      qb.andWhere(`${this.distanceKmSql} <= :rayonKm`, { rayonKm });
    }

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
      // Départage final — voir le commentaire de la branche par défaut : deux
      // promos de même remise et même instant de publication s'ordonnaient
      // arbitrairement, et `skip/take` faisait alors réapparaître ou
      // disparaître des lignes d'une page à l'autre. Le défaut existait déjà
      // ici avant la bascule ; le corriger d'un seul côté aurait laissé
      // l'autre (règle #30).
      qb.addOrderBy('promo.id', 'ASC');
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

    // Le tri par distance ne se demande pas, il se déduit : `sort` n'a **pas**
    // de valeur par défaut dans le DTO, donc `undefined` veut dire « le client
    // n'a rien demandé » et se distingue d'un `recent` explicite. Un client
    // déjà installé, qui n'envoie pas de position, garde donc exactement
    // l'ordre d'avant — ce que `list-promo-query.dto.ts` interdit de changer.
    //
    // Les favoris restent devant : c'est un choix explicite de l'utilisateur,
    // la proximité n'a pas à le lui reprendre.
    if (position && query.sort === undefined) {
      qb.addSelect(this.distanceKmSql, 'distance_km');
      qb.addOrderBy('distance_km', 'ASC');
    }

    // NULLS LAST : toutes les promos ici sont PUBLIEE donc publishedAt est
    // normalement toujours renseigné, mais une ligne pré-migration mal
    // backfillée ne doit pas remonter en tête d'un tri DESC (comportement
    // par défaut de Postgres pour NULL en DESC).
    qb.addOrderBy('promo.publishedAt', 'DESC', 'NULLS LAST');
    // ⚠️ **Départage déterministe, sans quoi la pagination n'est pas stable.**
    // Toutes les promos d'un même commerçant ont **exactement** la même
    // distance : sans ce dernier critère, l'ordre entre elles est arbitraire et
    // Postgres est libre de le changer d'une requête à l'autre — donc entre la
    // page 1 et la page 2, où `skip/take` fait alors réapparaître ou disparaître
    // des lignes. La pagination existait déjà (règle #15) ; c'est sa
    // **stabilité** qui manquait.
    qb.addOrderBy('promo.id', 'ASC');
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
    // Lu une fois pour toute la méthode : les trois usages (limite SQL, seuil
    // de troncature, découpe) doivent parler du **même** plafond. Trois
    // lectures de configuration indépendantes pourraient diverger si la valeur
    // changeait entre-temps, et la réponse dirait alors `truncated: false` sur
    // une liste tronquée.
    const plafond = this.maxMapCommercants();

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

    const commercantsQb = this.applyBoundingBox(
      visiblePromoConditions(
        this.promos
          .createQueryBuilder('promo')
          .innerJoin('promo.commercant', 'commercant'),
      )
        .andWhere('commercant.latitude IS NOT NULL')
        .andWhere('commercant.longitude IS NOT NULL'),
      query,
    )
      .select('commercant.id', 'id')
      .distinct(true)
      // +1 pour détecter le dépassement sans seconde requête de comptage.
      .limit(plafond + 1);

    if (query.categorie) {
      commercantsQb.andWhere('promo.categorie = :categorie', {
        categorie: query.categorie,
      });
    }

    const rows = await commercantsQb.getRawMany<{ id: string }>();
    const truncated = rows.length > plafond;
    const commercantIds = rows.slice(0, plafond).map((row) => row.id);
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
   * Où centrer la carte pour un client qui n'a pas (ou pas encore) de position
   * GPS, mais qui a choisi ses communes.
   *
   * ── Pourquoi ce calcul et pas une colonne ────────────────────────────────
   *
   * `Commune` ne porte **que** `id`/`nom`/`wilaya` — aucune coordonnée, et le
   * seed les crée par nom seul. Ajouter latitude/longitude aurait demandé
   * d'inventer 36 paires de coordonnées pour les communes de Djelfa : des
   * chiffres plausibles, faux, et impossibles à distinguer de vrais une fois
   * en base. On dérive donc le centre des **positions réelles** des
   * commerçants qui ont quelque chose à montrer.
   *
   * ── Ce qu'il renvoie quand il ne sait pas ────────────────────────────────
   *
   * `null`, jamais un point de repli. Une commune sans commerçant positionné
   * n'a pas de centre connu, et un centre inventé enverrait le client
   * regarder un endroit où il n'y a rien — en lui laissant croire qu'il n'y a
   * rien *là où il habite*. C'est l'appelant qui décide quoi faire de
   * l'absence (règle #29).
   *
   * La moyenne suffit ici : à l'échelle d'une commune algérienne les points
   * sont assez groupés pour qu'un barycentre tombe dans la zone habitée. Ce
   * ne serait plus vrai sur un territoire éclaté — à revoir à l'extension
   * multi-wilaya, pas avant.
   */
  async findMapCenterForCommunes(
    communeIds: string[],
  ): Promise<{ latitude: number; longitude: number } | null> {
    if (communeIds.length === 0) return null;

    // Les mêmes cinq conditions que partout ailleurs : le centre doit désigner
    // ce que la carte affichera, pas ce qui existe en base. Passer par
    // `applyVisibleConditions` plutôt que de les réécrire est ce qui le
    // garantit (règle #9).
    //
    // ⚠️ La moyenne se prend sur une sous-requête, pas directement.
    // `AVG(DISTINCT latitude)` et `AVG(DISTINCT longitude)` dédoublonneraient
    // **indépendamment** : ils dédupliquent des coordonnées, pas des
    // commerçants, et recomposeraient un point qui ne correspond à aucune
    // répartition réelle. Il faut dédoublonner le commerçant d'abord — sinon
    // un commerce à 5 promos pèse aussi cinq fois et tire le centre vers lui.
    const positions = this.applyVisibleConditions(
      this.promos
        .createQueryBuilder('promo')
        .innerJoin('promo.commercant', 'commercant'),
    )
      .andWhere('commercant.communeId IN (:...communeIds)', { communeIds })
      .andWhere('commercant.latitude IS NOT NULL')
      .andWhere('commercant.longitude IS NOT NULL')
      // `id` dans le SELECT : c'est lui qui rend le DISTINCT « par commerçant »
      // plutôt que « par couple de coordonnées » — deux commerces à la même
      // adresse restent deux points.
      .select('commercant.id', 'id')
      .addSelect('commercant.latitude', 'latitude')
      .addSelect('commercant.longitude', 'longitude')
      .distinct(true);

    const [sql, parameters] = positions.getQueryAndParameters();
    const rows = await this.promos.manager.query<
      { latitude: string | null; longitude: string | null }[]
    >(
      `SELECT AVG("latitude") AS latitude, AVG("longitude") AS longitude FROM (${sql}) AS positions`,
      parameters,
    );
    const row = rows[0];

    if (!row?.latitude || !row.longitude) return null;

    const latitude = Number(row.latitude);
    const longitude = Number(row.longitude);
    // `AVG` sort en chaîne côté pilote Postgres, et une chaîne illisible
    // donnerait `NaN` — que `JSON.stringify` sérialise en `null` sans erreur,
    // donc un centre absent déguisé en centre présent (règle #34).
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

    return { latitude, longitude };
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
    const commercant =
      await this.commercantService.findByIdOrFail(commercantId);
    return {
      enLigne,
      plafond: this.plafondActif(commercant.promoActiveCap),
    };
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

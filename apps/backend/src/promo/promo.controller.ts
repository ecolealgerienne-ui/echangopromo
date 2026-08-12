import {
  Body,
  Controller,
  Get,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { UuidParam } from '../common/decorators/uuid-param.decorator';
import { Throttle } from '@nestjs/throttler';
import { AuditLogService } from '../audit-log/audit-log.service';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { ForbiddenAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { MAP_THROTTLE, SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoMapQueryDto } from './dto/list-promo-map-query.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { Promo } from './entities/promo.entity';
import { PromoService } from './promo.service';

@Controller('promo')
export class PromoController {
  constructor(
    private readonly promoService: PromoService,
    private readonly storageService: StorageService,
    // ⚠️ `AgentService` et `CommercantService` ont été retirés d'ici le
    // 2026-08-13 : leur seul usage était de résoudre les communes de l'agent
    // pour les gardes d'appartenance. Sans elles, plus aucun appelant dans ce
    // contrôleur (règle #31).
    //
    // `CommercantModule` reste nécessaire à `PromoModule` — `PromoService` le
    // consomme (registre, profil, position, compte actif). `AgentModule`, lui,
    // n'a plus **aucun** consommateur dans `promo/` : retiré aussi.
    private readonly auditLogService: AuditLogService,
  ) {}

  /**
   * ⚠️ **Branché le 2026-08-13, et il aurait dû l'être depuis toujours.**
   * `createByAgent` exemptait agent et admin des limites anti-abus au motif
   * qu'ils « agissent via un canal audité » — mesuré : `AuditLogService`
   * n'était importé ni par ce contrôleur ni par `PromoModule`. **Le canal
   * n'était pas audité.** Un commentaire affirmait une couverture inexistante,
   * ce qui est le cas fondateur de la règle #11 dans sa forme la plus chère :
   * un module bien conçu, branché ailleurs, et une phrase qui dispense d'aller
   * voir.
   *
   * La commune bornait le trou : un agent ne pouvait agir que chez lui. Le
   * chantier « agent global » le rend national — d'où l'urgence de brancher
   * plutôt que d'assumer.
   *
   * Ne trace **que** les gestes agent/admin : une écriture de commerçant sur
   * sa propre promo est un usage normal du produit, pas un acte d'autorité.
   */
  private async auditStaffWrite(
    user: AuthTokenPayload,
    action: string,
    promoId: string,
    metadata?: Record<string, unknown>,
  ): Promise<void> {
    if (user.role === 'commercant') return;
    await this.auditLogService.record({
      actorType:
        user.role === 'agent' ? AuditActorType.AGENT : AuditActorType.ADMIN,
      actorId: user.sub,
      action,
      targetType: 'promo',
      targetId: promoId,
      metadata,
    });
  }

  /**
   * DTO de sortie explicite plutôt qu'un spread de l'entité (`{...promo}`) :
   * un spread transforme l'instance en objet plain et désactiverait
   * silencieusement les `@Exclude()` si l'entité en gagnait un jour ;
   * ça exclut aussi `photoKeys`, qui pour les promos créées par un agent
   * contient l'UUID de l'**agent** (pas du commerçant) — un identifiant
   * interne qui n'a rien à faire dans une réponse publique.
   *
   * `includeKeys` réexpose les clés S3 brutes (pas seulement les URLs) —
   * réservé à `GET /promo/me/all` (propriétaire authentifié uniquement) :
   * l'écran d'édition en a besoin pour renvoyer les photos inchangées sans
   * les réuploader, sans jamais les exposer publiquement.
   */
  private toClientJson(promo: Promo, options?: { includeKeys?: boolean }) {
    const photoUrls = promo.photoKeys.map((key) =>
      this.storageService.buildPublicUrl(key),
    );
    return {
      id: promo.id,
      commercantId: promo.commercantId,
      commercantNom: promo.commercant?.nom ?? null,
      /**
       * Position du commerce — pour que l'app puisse **afficher** la distance
       * dans la liste (bascule 2026-08-12, A7 du plan).
       *
       * Le serveur **ordonne** par distance, l'app **affiche** : la valeur
       * calculée en SQL sert au `ORDER BY` et n'est jamais rendue, parce que
       * `getManyAndCount()` jette les colonnes brutes d'un `addSelect` et que
       * la seule alternative — fusionner `{...promo, distanceKm}` — est le bug
       * fondateur de la règle #4 (le spread désactive les `@Exclude()`).
       *
       * ⚠️ L'ordre affiché reste **celui du serveur** : `distanceTo` côté app
       * sert au libellé, jamais à re-trier. Deux tris qui divergeraient d'un
       * epsilon donneraient une liste dont l'ordre contredit ses propres
       * étiquettes.
       *
       * N'ouvre aucune surface nouvelle : ces coordonnées sont déjà publiques
       * via `GET /promo/map`, qui les sert pour placer les épingles.
       */
      commercantLatitude: promo.commercant?.latitude ?? null,
      commercantLongitude: promo.commercant?.longitude ?? null,
      description: promo.description,
      prixAvant: promo.prixAvant,
      prixApres: promo.prixApres,
      categorie: promo.categorie,
      dateFin: promo.dateFin,
      lifecycleStatus: promo.lifecycleStatus,
      moderationStatus: promo.moderationStatus,
      photoUrls,
      // Miniature de la 1ère photo (listes, audit performance 2026-07-12) —
      // retombe sur la photo complète si la génération a échoué (best-effort,
      // voir `PromoService.tryGenerateThumbnail`), jamais `null` tant qu'il y
      // a au moins une photo.
      thumbnailUrl: promo.thumbnailKey
        ? this.storageService.buildPublicUrl(promo.thumbnailKey)
        : (photoUrls[0] ?? null),
      ...(options?.includeKeys ? { photoKeys: promo.photoKeys } : {}),
      createdAt: promo.createdAt,
      publishedAt: promo.publishedAt,
    };
  }

  /**
   * Un commerçant ne peut agir que sur ses propres promos. **Un agent peut
   * agir sur toutes** depuis le 2026-08-13 (chantier « agent global ») : la
   * garde est devenue asymétrique, elle ne se supprime donc pas.
   *
   * ⚠️ La branche `commercant` ci-dessous est désormais la garde
   * d'appartenance **principale** de tout ce contrôleur — la seule autre
   * survivante est `assertPhotoKeysOwned` côté service. Elle n'était probée
   * par aucun banc avant ce chantier (`PROMO_NOT_OWNED_BY_COMMERCANT`
   * n'apparaissait qu'en code *accepté*, jamais provoqué) ; `commercant_b.py`
   * a été écrit pour ça, dans le même lot.
   */
  private assertCanManage(user: AuthTokenPayload, promo: Promo): void {
    if (user.role === 'commercant') {
      if (promo.commercantId !== user.sub) {
        throw new ForbiddenAppException(
          ErrorCode.PROMO_NOT_OWNED_BY_COMMERCANT,
          "Cette promo n'appartient pas à ce commerçant",
        );
      }
      return;
    }
    // Agent : aucune vérification d'appartenance. Règle #1 levée par décision
    // produit — il n'a plus de territoire à opposer.
  }

  @Get()
  async list(@Query() query: ListPromoQueryDto) {
    const result = await this.promoService.findActiveForClient(query);
    return {
      ...result,
      items: result.items.map((promo) => this.toClientJson(promo)),
    };
  }

  /**
   * Commerçants géolocalisés de la zone visible, avec leurs promos actives
   * (écran carte). Le regroupement en "ronds" se calcule côté app à partir
   * de ces positions — pas de clustering serveur, qui dépendrait du niveau
   * de zoom et de la taille d'écran.
   *
   * DOIT rester déclaré avant `@Get(':id')` : `map` est un segment unique,
   * il serait sinon capturé comme un identifiant de promo et répondrait
   * `PROMO_NOT_FOUND` au lieu d'atteindre cette méthode.
   */
  @Throttle(MAP_THROTTLE)
  @Get('map')
  async map(@Query() query: ListPromoMapQueryDto) {
    const { commercants, truncated } =
      await this.promoService.findActiveForMap(query);
    return {
      truncated,
      items: commercants.map(({ commercant, promos }) => ({
        id: commercant.id,
        nom: commercant.nom,
        categorie: commercant.categorie,
        adresse: commercant.adresse,
        telephone: commercant.telephone,
        latitude: commercant.latitude,
        longitude: commercant.longitude,
        photoUrl: commercant.photoKey
          ? this.storageService.buildPublicUrl(commercant.photoKey)
          : null,
        promos: promos.map((promo) => this.toClientJson(promo)),
      })),
    };
  }

  /**
   * Repères géographiques dont l'app a besoin **avant** de pouvoir demander
   * quoi que ce soit : où centrer la vue quand le client n'a rien enregistré,
   * quel rayon appliquer, et jusqu'où il peut l'élargir.
   *
   * ── Pourquoi une route, et pas des valeurs compilées ──────────────────────
   *
   * Le mobile n'a pas de `.env` (`lib/config/env.dart` n'expose que des
   * `String.fromEnvironment`, figés au build — et qui **se perdent
   * silencieusement** selon la façon dont `flutter` est lancé, voir
   * `CLAUDE.md` § Environnement). Une valeur compilée ne se change qu'en
   * republiant sur les deux stores. Ici, c'est une ligne de `.env`.
   *
   * ⚠️ **Route publique et non authentifiée : elle ne doit jamais porter autre
   * chose que ces quatre nombres.** Tout ce qu'on y ajouterait par commodité
   * serait servi au monde entier. Elle est épinglée à ce titre dans
   * `scripts/lib/frontiere_http.py` (règle #33).
   *
   * Pas de `@Throttle` dédié : la limite globale (60/min/IP) suffit largement
   * pour un appel émis une fois au démarrage, et la réponse ne touche pas la
   * base. C'est un choix, pas un oubli.
   *
   * DOIT rester déclarée **avant** `@Get(':id')` — `config` est un segment
   * unique, il serait sinon capté comme un identifiant (même raison que
   * `@Get('map')`).
   */
  @Get('config')
  getClientConfig() {
    return this.promoService.getClientConfig();
  }

  /**
   * Route publique, non authentifiée (accessible via lien partagé/App Links
   * `/p/:id`). Le filtre de visibilité était réécrit ici et ne reprenait
   * qu'une des cinq conditions (`VISIBLE_MODERATION_STATUSES`) : une promo
   * arrêtée, expirée, en brouillon, ou d'un commerçant suspendu restait
   * intégralement consultable par quiconque avait le lien. La règle vit
   * maintenant dans `PromoService.applyVisibleConditions` et nulle part
   * ailleurs (revue 2026-08-05, règles #8 et #30).
   */
  @Get(':id')
  async detail(@UuidParam('id') id: string, @DeviceId() deviceId: string) {
    const promo = await this.promoService.findVisibleByIdOrFail(id);
    await this.promoService.recordView(id, deviceId);
    return this.toClientJson(promo);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Post()
  async create(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreatePromoDto,
  ) {
    return this.promoService.create(user.sub, dto);
  }

  /**
   * Occupation du plafond de promos actives — servie ici plutôt que dans
   * `GET /commercant/me` : `CommercantController` n'injecte pas `PromoService`,
   * et l'y injecter fermerait un cycle de modules (`PromoModule` importe déjà
   * `CommercantModule`). Recopier la règle du plafond côté commerçant serait
   * exactement ce que la règle #9 interdit — c'est le propriétaire de la règle
   * qui la sert.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/slots')
  async mySlots(@CurrentUser() user: AuthTokenPayload) {
    return this.promoService.getSlotUsage(user.sub);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/all')
  async mine(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: PaginationQueryDto,
  ) {
    const result = await this.promoService.listByCommercant(
      user.sub,
      query.page,
      query.limit,
    );
    const viewCounts = await this.promoService.getViewCounts(
      result.items.map((p) => p.id),
    );
    return {
      ...result,
      items: result.items.map((promo) => ({
        ...this.toClientJson(promo, { includeKeys: true }),
        viewCount: viewCounts[promo.id] ?? 0,
      })),
    };
  }

  /**
   * IDOR corrigé : un agent ne peut publier que pour un commerçant de ses
   * propres communes — pas de restriction de commune pour un admin (vue
   * globale, décision produit 2026-07-12 : l'admin gagne la même capacité
   * de publier pour un commerçant, écrans partagés avec l'agent).
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent', 'admin')
  @Post('agent/:commercantId')
  async createByAgent(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('commercantId') commercantId: string,
    @Body() dto: CreatePromoDto,
  ) {
    // ⚠️ **Ici se trouvait la 14ᵉ garde d'appartenance, retirée le
    // 2026-08-13** — et c'était la seule appelée EN PROPRE plutôt que via
    // `assertCanManage`, donc invisible à un grep sur cette méthode. Deux
    // relectures l'ont manquée pour cette raison.
    //
    // C'est très exactement la route que la règle #1 de `CLAUDE.md` nomme
    // comme l'IDOR fondateur (« `PromoController.createByAgent` »), et c'est
    // la seule route d'écriture de promo que l'app appelle réellement pour un
    // agent. La rouvrir est une décision produit (« agent global ») ; la
    // rouvrir sans le dire serait rejouer l'IDOR d'origine à son endroit
    // d'origine.
    //
    // Exempté des plafonds anti-abus (2026-07-14) : agent/admin agissent via
    // un canal audité — ce qui est vrai depuis le 2026-08-13 seulement, voir
    // `auditStaffWrite`. Deux limites sont levées, la création 5/24 h et le
    // cooldown de republication ; le plafond de promos ACTIVES, lui, ne l'est
    // pas et s'applique à tout le monde.
    // `actorId` : les clés S3 uploadées par un agent portent SON `sub`
    // (`StorageController.upload`), pas celui du commerçant — sans ça la
    // garde d'appartenance refuserait la promo que l'agent vient de saisir.
    const promo = await this.promoService.create(commercantId, dto, {
      trustedActor: true,
      actorId: user.sub,
    });
    await this.auditStaffWrite(user, 'promo_create_by_staff', promo.id, {
      commercantId,
    });
    return promo;
  }

  /** Édition ouverte au commerçant propriétaire, en plus de l'agent (auparavant agent uniquement). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Patch(':id')
  async update(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') id: string,
    @Body() dto: UpdatePromoDto,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    this.assertCanManage(user, promo);
    const updated = await this.promoService.update(id, dto, {
      actorId: user.sub,
    });
    await this.auditStaffWrite(user, 'promo_update_by_staff', id, {
      commercantId: promo.commercantId,
    });
    return updated;
  }

  /**
   * Publie un brouillon, ou republie une promo arrêtée/expirée (specs §3.2).
   * L'agent est exempté du cooldown anti-abus de republication (même
   * raisonnement que `createByAgent`) — jamais le commerçant lui-même.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Post(':id/publish')
  async publish(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') id: string,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    this.assertCanManage(user, promo);
    const published = await this.promoService.publish(id, {
      trustedActor: user.role === 'agent',
    });
    await this.auditStaffWrite(user, 'promo_publish_by_staff', id, {
      commercantId: promo.commercantId,
    });
    return published;
  }

  /** Arrêt volontaire (ex. rupture de stock) — libère un slot sur le plafond de 5. */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant', 'agent')
  @Post(':id/stop')
  async stop(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') id: string,
  ) {
    const promo = await this.promoService.findByIdOrFail(id);
    this.assertCanManage(user, promo);
    const stopped = await this.promoService.stop(id);
    await this.auditStaffWrite(user, 'promo_stop_by_staff', id, {
      commercantId: promo.commercantId,
    });
    return stopped;
  }
}

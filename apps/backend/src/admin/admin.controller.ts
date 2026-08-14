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
import { AgentService } from '../agent/agent.service';
import { CreateAgentDto } from '../agent/dto/create-agent.dto';
import { ResetAgentPasswordDto } from '../agent/dto/reset-agent-password.dto';
import { AuditLogService } from '../audit-log/audit-log.service';
import { ListAuditLogQueryDto } from '../audit-log/dto/list-audit-log-query.dto';
import { UpdatePromoActiveCapDto } from './dto/update-promo-active-cap.dto';
import { AuditActorType } from '../audit-log/entities/audit-log.entity';
import { AuthService } from '../auth/auth.service';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CommercantService } from '../commercant/commercant.service';
import { ListCommercantQueryDto } from '../commercant/dto/list-commercant-query.dto';
import { ResetCommercantPinDto } from '../commercant/dto/reset-commercant-pin.dto';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { AUTH_THROTTLE, SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { ListModerationQueueQueryDto } from './dto/list-moderation-queue-query.dto';
import { ResolveModerationDto } from './dto/resolve-moderation.dto';
import { ListPromoAdminQueryDto } from '../promo/dto/list-promo-admin-query.dto';
import { Promo } from '../promo/entities/promo.entity';
import { PromoService } from '../promo/promo.service';
import { ReportService } from '../report/report.service';
import { StorageService } from '../storage/storage.service';
import { AdminService } from './admin.service';
import { LoginAdminDto } from './dto/login-admin.dto';
import { ModerationService } from './moderation.service';

@Controller('admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly agentService: AgentService,
    private readonly commercantService: CommercantService,
    private readonly promoService: PromoService,
    private readonly reportService: ReportService,
    private readonly authService: AuthService,
    private readonly auditLogService: AuditLogService,
    private readonly moderationService: ModerationService,
    private readonly storageService: StorageService,
  ) {}

  @Throttle(AUTH_THROTTLE)
  @Post('login')
  async login(@Body() dto: LoginAdminDto) {
    const admin = await this.adminService.login(dto.email, dto.password);
    return {
      accessToken: this.authService.issueToken(
        admin.id,
        'admin',
        admin.tokenVersion,
      ),
    };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.adminService.findByIdOrFail(user.sub);
  }

  /** Révoque tous les JWT déjà émis pour ce compte (device perdu/volé) — audit V1 §1. */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('me/revoke-token')
  async revokeOwnToken(@CurrentUser() user: AuthTokenPayload) {
    await this.adminService.revokeOwnTokens(user.sub);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'revoke_own_token',
      targetType: 'admin',
      targetId: user.sub,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent')
  async createAgent(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreateAgentDto,
  ) {
    const agent = await this.agentService.create(dto);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'create_agent',
      targetType: 'agent',
      targetId: agent.id,
    });
    return agent;
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('agent')
  async listAgents(@Query() query: PaginationQueryDto) {
    return this.agentService.findAll(query.page, query.limit);
  }

  // ⚠️ `PATCH agent/:id/communes` supprimée le 2026-08-13. Elle portait un
  // commentaire qui reste utile ailleurs : placé ENTRE les décorateurs de
  // garde et le verbe, il faisait lire la route comme **ouverte** par le banc
  // de frontière (2026-08-05). Le banc y est insensible depuis, mais la place
  // conventionnelle d'un commentaire reste au-dessus des décorateurs.

  /** Révoque les JWT déjà émis pour cet agent (device perdu/volé, départ — audit règle #6). */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent/:id/revoke-token')
  async revokeAgentToken(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') agentId: string,
  ) {
    await this.agentService.revokeTokens(agentId);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'revoke_agent_token',
      targetType: 'agent',
      targetId: agentId,
    });
    return { ok: true };
  }

  /**
   * Mot de passe agent oublié/perdu — l'agent ne peut pas le changer
   * lui-même (décision produit 2026-07-14), seul l'admin fixe un nouveau
   * mot de passe, à communiquer de vive voix. Même schéma que
   * `resetPin`/`reset-pin` côté commerçant.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Post('agent/:id/reset-password')
  async resetAgentPassword(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') agentId: string,
    @Body() dto: ResetAgentPasswordDto,
  ) {
    await this.agentService.resetPassword(agentId, dto.newPassword);
    await this.auditLogService.record({
      actorType: AuditActorType.ADMIN,
      actorId: user.sub,
      action: 'reset_agent_password',
      targetType: 'agent',
      targetId: agentId,
    });
    return { ok: true };
  }

  // ⚠️ `POST agent/transfer-communes` supprimée le 2026-08-13 (specs §3.4).
  // Elle répondait à un besoin métier réel que **rien ne reprend** : au départ
  // d'un agent, transférer son secteur pour que ses commerces ne cessent pas
  // d'être suivis en silence. Sans territoire, la question ne se pose plus.
  //
  // ⚠️ Les entrées d'audit `assign_agent_communes` et `transfer_communes`
  // restent en base, avec leurs `metadata.communeIds` pointant vers une table
  // supprimée. **Elles ne sont pas purgées** : c'est de la traçabilité
  // historique, et l'écran d'audit affiche `action` en brut, donc rien ne
  // casse.

  /**
   * DTO explicite plutôt qu'un spread d'entité (règle #4) — la file de
   * modération n'exposait ni photoUrl (jamais calculé, `photoKeys` est
   * @Exclude()) ni le contact du commerçant, rendant la décision de
   * modération difficile sans ces informations. Partagé entre la file
   * automatique et la liste globale (`/admin/promo`, Phase 2).
   */
  private toAdminPromoJson(promo: Promo) {
    const photoUrls = promo.photoKeys.map((key) =>
      this.storageService.buildPublicUrl(key),
    );
    return {
      id: promo.id,
      description: promo.description,
      prixAvant: promo.prixAvant,
      prixApres: promo.prixApres,
      categorie: promo.categorie,
      photoUrls,
      // Miniature de la 1ère photo (liste de modération) — même fallback
      // que côté client si la génération a échoué.
      thumbnailUrl: promo.thumbnailKey
        ? this.storageService.buildPublicUrl(promo.thumbnailKey)
        : (photoUrls[0] ?? null),
      lifecycleStatus: promo.lifecycleStatus,
      moderationStatus: promo.moderationStatus,
      dateFin: promo.dateFin,
      commercantId: promo.commercant.id,
      commercantNom: promo.commercant.nom,
      commercantTelephone: promo.commercant.telephone,
    };
  }

  // ⚠️ **Trois méthodes ont été retirées ici le 2026-08-13, et c'est une
  // décision produit, pas un nettoyage** (chantier « agent global ») :
  //
  //   - `scopedCommuneIds` — projetait les listes sur les communes de l'agent ;
  //   - `assertCanModerate` — garde IDOR sur les 3 routes de modération ;
  //   - `assertCanManageCommercant` — garde IDOR sur les 7 routes de gestion.
  //
  // Les dix routes ci-dessous n'ont plus, pour seule protection, que leur
  // `@Roles('admin','agent')`. **C'est la règle #1 qu'on retire** : « le rôle
  // JWT ne suffit jamais pour une action sur la ressource d'un tiers ». Elle
  // avait pour cas fondateur exactement cet endroit.
  //
  // C'est écrit ici, et rappelé à chacune des dix routes, parce qu'une garde
  // retirée sans un mot est indiscernable d'une garde jamais branchée — c'est
  // la règle #10 prise à l'envers, et c'est ainsi que l'IDOR d'origine était
  // passé la première fois.
  //
  // ⚠️ Le cas dégénéré s'INVERSE : un agent sans aucune commune était arrêté
  // net (huit sites rendaient 0 ou une page vide). Il voyait **zéro**, il voit
  // désormais **tout**. Le compte le plus mal configuré du parc est celui qui
  // change le plus.

  private actorType(role: string): AuditActorType {
    return role === 'agent' ? AuditActorType.AGENT : AuditActorType.ADMIN;
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('moderation/queue')
  async moderationQueue(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: ListModerationQueueQueryDto,
  ) {
    // Portée globale depuis le 2026-08-13 : `undefined` = aucun filtre de
    // commune. ⚠️ **Tous les agents voient désormais la MÊME file**, et la
    // commune tenait lieu de partition du travail : rien ne la remplace à ce
    // jour — point ouvert du plan de suppression.
    //
    // ⚠️ **Ce commentaire affirmait, jusqu'au 2026-08-13 au soir, que les trois
    // résolutions étaient des `update` inconditionnels où « dernier écrivain
    // gagne, aucune erreur levée ».** C'était vrai le matin, faux le soir, et
    // c'est exactement le genre d'état périmé qui fait conclure : on lit, on
    // croit la perte de décision ouverte, on part la refermer une seconde fois.
    // Chaque résolution porte désormais l'état que le modérateur avait à
    // l'écran (`expectedModerationStatus`), l'écriture y est conditionnée, et
    // une décision prise sur un état dépassé rend `409
    // MODERATION_STATE_CHANGED` — éprouvé par `test-moderation-course.sh`,
    // mutation comprise.
    //
    // **Répartir le travail reste à faire ; le corrompre n'est plus possible en
    // silence.** L'entrée et la sortie de cette file sont éprouvées par
    // `test-file-moderation.sh`, qui mesure aussi le seuil de trois appareils
    // distincts : un signalement isolé ne crée aucun travail.
    const result = await this.moderationService.queue(query.page, query.limit);
    return {
      ...result,
      items: result.items.map(
        ({ promo, activeReportCount, reasonBreakdown }) => ({
          ...this.toAdminPromoJson(promo),
          activeReportCount,
          reasonBreakdown,
        }),
      ),
    };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/masquer')
  async masquer(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('promoId') promoId: string,
    @Body() dto: ResolveModerationDto,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent modère n'importe quelle promo du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    //
    // ⚠️ **C'est ce retrait qui a rendu la course réelle** : la file est
    // devenue nationale et non partitionnée, donc tous les agents du pays
    // regardent la même liste sans que rien ne leur attribue un lot. D'où
    // `expectedModerationStatus`, qui fait porter la décision par l'état que le
    // modérateur avait à l'écran (voir `ResolveModerationDto`).
    await this.moderationService.masquer(
      this.actorType(user.role),
      user.sub,
      promoId,
      dto.expectedModerationStatus,
    );
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/verifier-ok')
  async verifierOk(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('promoId') promoId: string,
    @Body() dto: ResolveModerationDto,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent modère n'importe quelle promo du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    //
    // ⚠️ **La plus coûteuse des trois à perdre dans une course** : elle rend la
    // promo publique ET ouvre une fenêtre d'ignore de 30 jours qui la rend
    // insensible aux signalements suivants. Écraser un « masquer » avec elle,
    // c'est republier un contenu retiré et le protéger un mois.
    await this.moderationService.verifierOk(
      this.actorType(user.role),
      user.sub,
      promoId,
      dto.expectedModerationStatus,
    );
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('moderation/:promoId/avertir')
  async avertir(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('promoId') promoId: string,
    @Body() dto: ResolveModerationDto,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent modère n'importe quelle promo du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    //
    // ⚠️ Elle **lève tout statut bloquant** (voir `resolveAvertir`) : écraser
    // un « masquer » avec elle rend la promo republiable par son commerçant,
    // masque levé, sans que personne n'ait décidé de le lever.
    await this.moderationService.avertir(
      this.actorType(user.role),
      user.sub,
      promoId,
      dto.expectedModerationStatus,
    );
    return { ok: true };
  }

  /**
   * Vue globale de toutes les promos (plan de correction, Phase 2) — la
   * file de modération n'expose que celles ayant atteint le seuil de
   * signalements ; ceci permet de repérer et masquer un contenu
   * problématique directement, sans attendre 3 signalements clients.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('promo')
  async listPromos(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: ListPromoAdminQueryDto,
  ) {
    // Portée globale depuis le 2026-08-13 (chantier « agent global »).
    const result = await this.promoService.findAllForAdmin(query);
    return {
      ...result,
      items: result.items.map((promo) => this.toAdminPromoJson(promo)),
    };
  }

  /**
   * Liste + recherche sur l'ensemble des commerçants (plan de correction,
   * Phase 2). `registreStatus` sert de filtre "en attente de validation" —
   * l'ancienne file dédiée (`GET commercant/registre/queue`) a été retirée
   * le 2026-07-11 au profit de ce filtre + de la fiche détail commerçant,
   * qui affiche désormais le registre et permet de le valider/rejeter.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('commercant')
  async listCommercants(
    @CurrentUser() user: AuthTokenPayload,
    @Query() query: ListCommercantQueryDto,
  ) {
    // Portée globale depuis le 2026-08-13 (chantier « agent global »).
    // ⚠️ La `CommuneFilterBar` de l'app disparaît avec ce chantier. Le seul
    // moyen de resserrer géographiquement cet écran devenu national est
    // désormais la recherche texte, à laquelle `adresse` a été ajoutée dans le
    // même lot (voir `findAllForAdmin`).
    const result = await this.commercantService.findAllForAdmin(query);
    return {
      ...result,
      items: await Promise.all(
        result.items.map(async (commercant) => ({
          id: commercant.id,
          nom: commercant.nom,
          telephone: commercant.telephone,
          adresse: commercant.adresse,
          categorie: commercant.categorie,
          photoUrl: commercant.photoKey
            ? this.storageService.buildPublicUrl(commercant.photoKey)
            : null,
          latitude: commercant.latitude,
          longitude: commercant.longitude,
          accountState: commercant.accountState,
          originVerification: commercant.originVerification,
          registreStatus: commercant.registreStatus,
          // URL pré-signée à courte durée de vie, jamais l'ACL publique
          // permanente utilisée pour les photos (audit sécurité
          // 2026-07-11 : le registre est un justificatif d'identité, pas
          // un contenu destiné au public — voir `StorageService.PRIVATE_FOLDERS`).
          registreUrl: commercant.registreKey
            ? await this.storageService.getPresignedUrl(commercant.registreKey)
            : null,
          profilePendingReview: commercant.profilePendingReview,
          // ⚠️ Servi tel quel, `null` compris : `null` veut dire « suit le
          // réglage global », et l'écran admin affiche deux textes distincts
          // selon le cas. L'omettre de cette projection ferait afficher
          // « global » quel que soit le réglage — un écran qui ment sans
          // erreur ni journal.
          promoActiveCap: commercant.promoActiveCap,
          suspended: commercant.suspendedAt !== null,
          deleted: commercant.deletedAt !== null,
          createdAt: commercant.createdAt,
        })),
      ),
    };
  }

  /**
   * Suspend un compte — réversible et arbitraire, distinct de la
   * suppression depuis le 2026-07-14 (voir `CommercantService.suspend`).
   * `assertCanManageCommercant` d'abord (IDOR, règle #1) ; l'existence du
   * commerçant est vérifiée par le service lui-même.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/suspend')
  async suspendCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.suspend(commercantId);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'commercant_suspend',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * Plafond de promos actives **propre à ce commerçant** ; `null` le remet sur
   * le réglage global (`PROMO_ACTIVE_CAP`).
   *
   * ⚠️ **Admin seulement, contrairement à suspendre/réactiver.** Accorder plus
   * d'emplacements à un commerce est une décision commerciale, pas un geste de
   * terrain : un agent qui peut l'ajuster peut avantager un commerçant de sa
   * commune sans que personne ne l'ait décidé. Le journal d'audit garde donc
   * une trace d'un geste qui n'a qu'un seul auteur possible.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Patch('commercant/:id/plafond-promos')
  async setCommercantPromoCap(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
    @Body() dto: UpdatePromoActiveCapDto,
  ) {
    await this.commercantService.setPromoActiveCap(commercantId, dto.plafond);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'commercant_promo_cap',
      targetType: 'commercant',
      targetId: commercantId,
      // Le journal doit dire CE QUI a été posé : « plafond modifié » sans la
      // valeur ne permet pas de reconstituer une décision commerciale.
      metadata: { plafond: dto.plafond },
    });
    return { ok: true };
  }

  /** Lève une suspension (voir `CommercantService.unsuspend`) — pas de republication automatique des promos. */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/reactivate')
  async reactivateCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.unsuspend(commercantId);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'commercant_reactivate',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * Suppression logique par l'admin/agent (nouvelle capacité, 2026-07-14) —
   * distincte de la suspension : libère le numéro de téléphone et
   * "supprime" les promos du commerçant (voir `CommercantService.deleteCommercant`).
   * Pas de restauration prévue, contrairement à la suspension.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/delete')
  async deleteCommercant(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.deleteCommercant(commercantId);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'commercant_delete',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/registre/valider')
  async validerRegistre(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      true,
    );
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'registre_valider',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * Valide une modification de profil en attente (`profilePendingReview`)
   * — débloque la publication de promo, s'applique à tous les commerçants
   * quelle que soit leur origine de vérification (décision produit
   * 2026-07-12).
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/profile/valider')
  async validerProfil(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.validateProfile(commercantId);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'profile_valider',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * PIN vraiment oublié (le commerçant ne peut fournir aucun ancien PIN) —
   * l'admin/agent fixe un nouveau PIN et le communique par téléphone après
   * avoir identifié l'appelant pendant la conversation (§3.2, décision
   * produit 2026-07-13 : remplace l'ancienne remise à zéro suivie d'une
   * revendication publique, exploitable par quiconque connaissait juste le
   * numéro de téléphone du commerçant).
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/reset-pin')
  async resetPin(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
    @Body() dto: ResetCommercantPinDto,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.resetPin(commercantId, dto.newPin);
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'commercant_reset_pin',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Post('commercant/:id/registre/rejeter')
  async rejeterRegistre(
    @CurrentUser() user: AuthTokenPayload,
    @UuidParam('id') commercantId: string,
  ) {
    // ⚠️ Plus aucune garde d'appartenance ici depuis le 2026-08-13 (agent
    // global) : n'importe quel agent gère n'importe quel commerçant du pays.
    // Voir le bloc « trois méthodes retirées » plus haut. Règle #1 levée.
    await this.commercantService.resolveRegistreVerification(
      commercantId,
      false,
    );
    await this.auditLogService.record({
      actorType: this.actorType(user.role),
      actorId: user.sub,
      action: 'registre_rejeter',
      targetType: 'commercant',
      targetId: commercantId,
    });
    return { ok: true };
  }

  /**
   * Journal d'audit consultable (plan de correction, Phase 3) — **admin
   * seulement**, y compris pour les actions enregistrées par un agent : un
   * agent ne voit pas ce journal, seul l'admin doit pouvoir retracer « qui a
   * fait quoi ».
   *
   * ⚠️ **Cette phrase citait « transfert de communes » comme exemple** — une
   * route supprimée le 2026-08-13. L'exemple était mort et la règle vivante.
   *
   * ⚠️ **Ce journal est devenu le seul contrepoids à la portée globale de
   * l'agent** (`CLAUDE.md`), depuis que les quatorze gardes d'appartenance sont
   * tombées le 2026-08-13 : il n'existe plus aucune limite *a priori* à ce
   * qu'un agent peut faire, seulement une trace *a posteriori*. Trois
   * mécanismes distincts l'alimentent pour un agent —
   * `PromoController.auditStaffWrite`, `ModerationService.record`, et les onze
   * appels en ligne de ce contrôleur — et ils sont éprouvés ensemble par
   * `test-journal-agent.sh`, qui vérifie surtout l'**attribution** : un journal
   * qui dit « un agent » sans dire lequel ne vaut rien quand tous sont globaux.
   *
   * ⚠️ **« n'expose que des UUID » était écrit ici, et c'est faux depuis le
   * 2026-08-13** : `findAll` appelle `resoudreLibelles`, qui résout le nom de
   * l'acteur et celui de la cible en une requête par table — y compris pour les
   * comptes supprimés, sans quoi une trace deviendrait illisible le jour où
   * elle compte le plus. Ce qui reste vrai : le journal **ne se filtre que par
   * `actorType`** (page et limite mises à part), ce qui suffit pour un parc de
   * commune et pas pour un parc national. Point ouvert, mais pas celui qui
   * était écrit.
   *
   * Le filtre, lui, est éprouvé : `test-journal-agent.sh` §8 exerce
   * `?actorType=agent` **et** `?actorType=admin`, et refuse si l'un laisse
   * passer l'autre.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin')
  @Get('audit-log')
  async auditLog(@Query() query: ListAuditLogQueryDto) {
    return this.auditLogService.findAll(
      query.page,
      query.limit,
      query.actorType,
    );
  }

  /**
   * Dashboard (specs §3.4) — partagé admin/agent (décision produit
   * 2026-07-12). ⚠️ **Les cinq compteurs sont globaux pour les deux rôles
   * depuis le 2026-08-13** : un agent et un admin voient exactement les mêmes
   * chiffres. Rien à l'écran ne distingue « mes commerces » de « tous » —
   * c'est voulu, l'agent n'ayant plus de territoire.
   */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('admin', 'agent')
  @Get('dashboard')
  async dashboard() {
    const [
      commercesActifs,
      promosPubliees,
      signalementsEnAttente,
      registresEnAttente,
      profilsEnAttente,
    ] = await Promise.all([
      this.commercantService.countActive(),
      this.promoService.countVisible(),
      this.reportService.countPendingModeration(),
      this.commercantService.countPendingRegistre(),
      this.commercantService.countPendingProfileReview(),
    ]);

    return {
      commercesActifs,
      promosPubliees,
      signalementsEnAttente,
      registresEnAttente,
      profilsEnAttente,
    };
  }
}

import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
// ⚠️ **Accès direct aux entités d'autres modules** (règle 9). Importer
// `AgentModule`, `AdminModule`, `CommercantModule` et `PromoModule` créerait
// quatre cycles : tous les quatre dépendent déjà d'`AuditLogModule` pour
// écrire. On lit donc les tables en direct, en LECTURE SEULE et sans jamais
// reproduire une règle métier de leur service — le seul besoin ici est de
// remplacer un UUID par un libellé.
import { Admin } from '../admin/entities/admin.entity';
import { Agent } from '../agent/entities/agent.entity';
import { Commercant } from '../commercant/entities/commercant.entity';
import {
  PaginatedResult,
  toPaginatedResult,
} from '../common/pagination/paginated-result';
import { Promo } from '../promo/entities/promo.entity';
import { AuditActorType, AuditLog } from './entities/audit-log.entity';

export interface AuditLogEntry {
  actorType: AuditActorType;
  actorId: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
}

/**
 * Une entrée telle qu'elle est servie — **pas l'entité**.
 *
 * ⚠️ Champ par champ, jamais `{...entity, actorLabel}` : un spread transforme
 * l'instance en objet plain et désactive silencieusement le
 * `ClassSerializerInterceptor` (règle 4). `AuditLog` n'a rien d'`@Exclude()`
 * aujourd'hui, mais la forme protège du jour où l'on en ajoutera un.
 */
export interface AuditLogView {
  id: string;
  actorType: AuditActorType;
  actorId: string;
  actorLabel: string | null;
  action: string;
  targetType: string | null;
  targetId: string | null;
  targetLabel: string | null;
  metadata: Record<string, unknown> | null;
  createdAt: Date;
}

@Injectable()
export class AuditLogService {
  constructor(
    @InjectRepository(AuditLog)
    private readonly auditLogs: Repository<AuditLog>,
    @InjectRepository(Agent) private readonly agents: Repository<Agent>,
    @InjectRepository(Admin) private readonly admins: Repository<Admin>,
    @InjectRepository(Commercant)
    private readonly commercants: Repository<Commercant>,
    @InjectRepository(Promo) private readonly promos: Repository<Promo>,
  ) {}

  async record(entry: AuditLogEntry): Promise<void> {
    await this.auditLogs.save(
      this.auditLogs.create({
        actorType: entry.actorType,
        actorId: entry.actorId,
        action: entry.action,
        targetType: entry.targetType ?? null,
        targetId: entry.targetId ?? null,
        metadata: entry.metadata ?? null,
      }),
    );
  }

  /**
   * Lecture paginée (plan de correction, Phase 3) — `record()` écrivait
   * déjà depuis le premier commit du backend (modération, reset PIN...) mais
   * rien ne permettait de la relire, seule une requête SQL manuelle sur le VPS
   * le pouvait.
   *
   * ── ⚠️ Les libellés, et pourquoi ils ne sont pas du confort ────────────────
   *
   * Jusqu'au 2026-08-13, cette réponse ne portait que des **UUID** : l'écran
   * affichait `agent 3f2a…` et `commercant 9c11…`. Personne ne peut retracer
   * « qui a fait quoi » là-dedans sans ouvrir la base à côté.
   *
   * C'était supportable tant que l'agent était borné à ses communes : la
   * question « de qui s'agit-il » avait une réponse courte. Depuis que les
   * quatorze gardes d'appartenance sont tombées, **ce journal est le seul
   * contrepoids à la portée globale** (`CLAUDE.md`) — il n'existe plus de
   * limite *a priori*, seulement une trace *a posteriori*. Une trace illisible
   * n'est pas un contrepoids : c'est un contrepoids qu'on croit avoir.
   *
   * ── ⚠️ Un libellé introuvable vaut `null`, jamais une chaîne de repli ─────
   *
   * « Agent supprimé » ou « — » écrirait une information qu'on n'a pas, et
   * rendrait indiscernables « l'acteur n'existe plus » et « je n'ai pas su le
   * résoudre » (règle 29). `null` laisse le client afficher l'UUID, qui reste
   * la seule vérité disponible.
   *
   * ⚠️ **Les comptes supprimés sont résolus quand même** : on lit les tables
   * sans le filtre `deletedAt IS NULL` des services. Un journal d'audit qui
   * perd le nom d'un commerçant le jour où on le supprime perd sa valeur
   * exactement quand elle compte — c'est la suppression qu'on veut pouvoir
   * retracer.
   */
  async findAll(
    page: number,
    limit: number,
    actorType?: AuditActorType,
  ): Promise<PaginatedResult<AuditLogView>> {
    const [items, total] = await this.auditLogs.findAndCount({
      where: actorType ? { actorType } : {},
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });

    const libelles = await this.resoudreLibelles(items);
    const vues = items.map((entree) => ({
      id: entree.id,
      actorType: entree.actorType,
      actorId: entree.actorId,
      actorLabel:
        libelles.get(this.cle(entree.actorType, entree.actorId)) ?? null,
      action: entree.action,
      targetType: entree.targetType,
      targetId: entree.targetId,
      targetLabel:
        entree.targetType && entree.targetId
          ? (libelles.get(this.cle(entree.targetType, entree.targetId)) ?? null)
          : null,
      metadata: entree.metadata,
      createdAt: entree.createdAt,
    }));
    return toPaginatedResult(vues, total, page, limit);
  }

  private cle(type: string, id: string): string {
    return `${type}:${id}`;
  }

  /**
   * ⚠️ **Une requête par TABLE, pas une par entrée** (règle 14). Le pattern
   * `Promise.all(items.map(async (e) => repo.findOne(...)))` est un N+1
   * quasi certain, et il l'aurait été ici sur une page de 100 entrées : jusqu'à
   * 200 requêtes pour afficher un écran. Quatre requêtes suffisent, quel que
   * soit le nombre d'entrées.
   *
   * Les identifiants sont dédupliqués avant : une même personne apparaît
   * typiquement sur des dizaines de lignes d'affilée.
   */
  private async resoudreLibelles(
    entrees: AuditLog[],
  ): Promise<Map<string, string>> {
    const parType = new Map<string, Set<string>>();
    const collecter = (type: string | null, id: string | null): void => {
      if (!type || !id) return;
      if (!parType.has(type)) parType.set(type, new Set());
      parType.get(type)!.add(id);
    };
    for (const e of entrees) {
      collecter(e.actorType, e.actorId);
      collecter(e.targetType, e.targetId);
    }

    const libelles = new Map<string, string>();
    const ids = (type: string): string[] => [...(parType.get(type) ?? [])];

    // `agent` est à la fois un type d'acteur et un type de cible (création
    // d'agent, révocation, réinitialisation de mot de passe) — une seule
    // requête couvre les deux.
    if (ids('agent').length > 0) {
      for (const a of await this.agents.find({
        where: { id: In(ids('agent')) },
        select: ['id', 'nom', 'email'],
      })) {
        libelles.set(this.cle('agent', a.id), `${a.nom} (${a.email})`);
      }
    }
    if (ids('admin').length > 0) {
      for (const a of await this.admins.find({
        where: { id: In(ids('admin')) },
        select: ['id', 'nom', 'email'],
      })) {
        libelles.set(this.cle('admin', a.id), `${a.nom} (${a.email})`);
      }
    }
    if (ids('commercant').length > 0) {
      for (const c of await this.commercants.find({
        where: { id: In(ids('commercant')) },
        select: ['id', 'nom', 'telephone'],
      })) {
        libelles.set(this.cle('commercant', c.id), `${c.nom} (${c.telephone})`);
      }
    }
    if (ids('promo').length > 0) {
      for (const p of await this.promos.find({
        where: { id: In(ids('promo')) },
        select: ['id', 'description'],
      })) {
        libelles.set(this.cle('promo', p.id), p.description);
      }
    }
    // `highlight` n'est pas résolu : une mise en avant n'a pas de libellé
    // propre (elle pointe une promo ou porte une image importée). Son UUID
    // reste affiché — dit ici plutôt que laissé deviner.
    return libelles;
  }
}

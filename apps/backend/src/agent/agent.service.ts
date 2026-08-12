import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import {
  PaginatedResult,
  toPaginatedResult,
} from '../common/pagination/paginated-result';
import { CreateAgentDto } from './dto/create-agent.dto';
import { Agent } from './entities/agent.entity';

@Injectable()
export class AgentService {
  constructor(
    @InjectRepository(Agent) private readonly agents: Repository<Agent>,
    private readonly authService: AuthService,
  ) {}

  /** Créé exclusivement par l'admin — pas d'auto-inscription agent (specs §3.3). */
  async create(dto: CreateAgentDto): Promise<Agent> {
    const existing = await this.agents.findOne({ where: { email: dto.email } });
    if (existing) {
      throw new BadRequestAppException(
        ErrorCode.AGENT_EMAIL_TAKEN,
        'Cet email est déjà utilisé par un agent',
      );
    }

    const passwordHash = await this.authService.hash(dto.password);
    return this.agents.save(
      this.agents.create({
        email: dto.email,
        nom: dto.nom,
        passwordHash,
      }),
    );
  }

  async login(email: string, password: string): Promise<Agent> {
    const agent = await this.agents.findOne({ where: { email } });
    if (!agent) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }
    const matches = await this.authService.compare(
      password,
      agent.passwordHash,
    );
    if (!matches) {
      throw new BadRequestAppException(
        ErrorCode.AUTH_INVALID_CREDENTIALS,
        'Identifiants invalides',
      );
    }
    return agent;
  }

  async findByIdOrFail(id: string): Promise<Agent> {
    const agent = await this.agents.findOne({
      where: { id },
    });
    if (!agent) {
      throw new NotFoundAppException(
        ErrorCode.AGENT_NOT_FOUND,
        'Agent introuvable',
      );
    }
    return agent;
  }

  async findAll(page: number, limit: number): Promise<PaginatedResult<Agent>> {
    const [items, total] = await this.agents.findAndCount({
      order: { nom: 'ASC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  // ⚠️ `assignCommunes` et `transferCommunes` ont été supprimées le
  // 2026-08-13 avec la relation `agent_communes`. Elles étaient le seul moyen
  // dont l'admin disposait pour **restreindre** un agent ; il n'y a plus
  // aucune granularité entre « agent » et « admin moins deux écrans ».
  //
  // `transferCommunes` répondait à un besoin métier réel que rien ne reprend :
  // au départ d'un agent, transférer son secteur pour que ses commerces ne
  // cessent pas d'être suivis en silence. Sans territoire, la question ne se
  // pose plus — mais la question inverse s'ouvre : plus rien n'attribue le
  // travail, et tous les agents voient la même file de modération.

  /** Révoque tous les JWT déjà émis pour cet agent (device perdu/volé, départ) — audit règle #6. */
  async revokeTokens(agentId: string): Promise<void> {
    await this.findByIdOrFail(agentId);
    await this.agents.increment({ id: agentId }, 'tokenVersion', 1);
  }

  /**
   * Mot de passe agent conservé (2026-07-14, décision produit — pas de PIN
   * pour ce rôle), mais l'agent ne peut pas le changer lui-même : seul
   * l'admin peut le réinitialiser (perte/oubli, départ), à communiquer de
   * vive voix — même schéma que `resetPin` côté commerçant (tokenVersion
   * incrémenté pour révoquer immédiatement toute session en cours).
   */
  async resetPassword(agentId: string, newPassword: string): Promise<void> {
    await this.findByIdOrFail(agentId);
    const passwordHash = await this.authService.hash(newPassword);
    await this.agents.update({ id: agentId }, { passwordHash });
    await this.agents.increment({ id: agentId }, 'tokenVersion', 1);
  }
}

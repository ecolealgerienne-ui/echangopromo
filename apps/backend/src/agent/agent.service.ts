import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
import { CommuneService } from '../commune/commune.service';
import {
  BadRequestAppException,
  NotFoundAppException,
} from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import { CreateAgentDto } from './dto/create-agent.dto';
import { Agent } from './entities/agent.entity';

@Injectable()
export class AgentService {
  constructor(
    @InjectRepository(Agent) private readonly agents: Repository<Agent>,
    private readonly authService: AuthService,
    private readonly communeService: CommuneService,
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

    const communes = await this.communeService.findByIds(dto.communeIds ?? []);
    const passwordHash = await this.authService.hash(dto.password);
    return this.agents.save(
      this.agents.create({
        email: dto.email,
        nom: dto.nom,
        passwordHash,
        communes,
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
      relations: ['communes'],
    });
    if (!agent) {
      throw new NotFoundAppException(ErrorCode.AGENT_NOT_FOUND, 'Agent introuvable');
    }
    return agent;
  }

  async findAll(page: number, limit: number): Promise<PaginatedResult<Agent>> {
    const [items, total] = await this.agents.findAndCount({
      relations: ['communes'],
      order: { nom: 'ASC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  /** Remplace l'ensemble des communes assignées à l'agent (liste vide = désassignation totale). */
  async assignCommunes(agentId: string, communeIds: string[]): Promise<Agent> {
    const agent = await this.findByIdOrFail(agentId);
    agent.communes = await this.communeService.findByIds(communeIds);
    return this.agents.save(agent);
  }

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

  /**
   * Transfère un lot de communes d'un agent à un autre (specs §3.4) — cas
   * type : départ d'un agent, pour éviter que les commerces de ces communes
   * cessent d'être suivis silencieusement.
   */
  async transferCommunes(
    communeIds: string[],
    fromAgentId: string,
    toAgentId: string,
  ): Promise<void> {
    const fromAgent = await this.findByIdOrFail(fromAgentId);
    const toAgent = await this.findByIdOrFail(toAgentId);

    const fromAgentCommuneIds = new Set(fromAgent.communes.map((c) => c.id));
    if (!communeIds.every((id) => fromAgentCommuneIds.has(id))) {
      throw new BadRequestAppException(
        ErrorCode.AGENT_COMMUNE_NOT_ASSIGNED_TO_AGENT,
        "Au moins une de ces communes n'est pas actuellement assignée à cet agent",
      );
    }

    const transferredIds = new Set(communeIds);
    const communesToTransfer = fromAgent.communes.filter((c) => transferredIds.has(c.id));
    fromAgent.communes = fromAgent.communes.filter((c) => !transferredIds.has(c.id));
    const toAgentCommuneIds = new Set(toAgent.communes.map((c) => c.id));
    toAgent.communes = [
      ...toAgent.communes,
      ...communesToTransfer.filter((c) => !toAgentCommuneIds.has(c.id)),
    ];
    await this.agents.save([fromAgent, toAgent]);
  }
}

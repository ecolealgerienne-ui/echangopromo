import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AuthService } from '../auth/auth.service';
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
        zoneId: dto.zoneId ?? null,
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
    const agent = await this.agents.findOne({ where: { id } });
    if (!agent) {
      throw new NotFoundAppException(ErrorCode.AGENT_NOT_FOUND, 'Agent introuvable');
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

  async assignZone(agentId: string, zoneId: string | null): Promise<Agent> {
    const agent = await this.findByIdOrFail(agentId);
    agent.zoneId = zoneId;
    return this.agents.save(agent);
  }

  /** Révoque tous les JWT déjà émis pour cet agent (device perdu/volé, départ) — audit règle #6. */
  async revokeTokens(agentId: string): Promise<void> {
    await this.findByIdOrFail(agentId);
    await this.agents.increment({ id: agentId }, 'tokenVersion', 1);
  }

  /**
   * Transfère une zone d'un agent à un autre (specs §3.4) — cas type :
   * départ d'un agent, pour éviter que les fiches de la zone cessent d'être
   * mises à jour silencieusement.
   */
  async transferZone(
    zoneId: string,
    fromAgentId: string,
    toAgentId: string,
  ): Promise<void> {
    const fromAgent = await this.findByIdOrFail(fromAgentId);
    const toAgent = await this.findByIdOrFail(toAgentId);

    if (fromAgent.zoneId !== zoneId) {
      throw new BadRequestAppException(
        ErrorCode.AGENT_ZONE_NOT_ASSIGNED_TO_AGENT,
        "Cette zone n'est pas actuellement assignée à cet agent",
      );
    }

    fromAgent.zoneId = null;
    toAgent.zoneId = zoneId;
    await this.agents.save([fromAgent, toAgent]);
  }
}

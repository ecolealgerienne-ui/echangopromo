import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import { AuditActorType, AuditLog } from './entities/audit-log.entity';

export interface AuditLogEntry {
  actorType: AuditActorType;
  actorId: string;
  action: string;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
}

@Injectable()
export class AuditLogService {
  constructor(
    @InjectRepository(AuditLog)
    private readonly auditLogs: Repository<AuditLog>,
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
   * déjà depuis le premier commit du backend (transferts de communes,
   * modération, reset PIN...) mais rien ne permettait de la relire, seule
   * une requête SQL manuelle sur le VPS le pouvait.
   */
  async findAll(
    page: number,
    limit: number,
    actorType?: AuditActorType,
  ): Promise<PaginatedResult<AuditLog>> {
    const [items, total] = await this.auditLogs.findAndCount({
      where: actorType ? { actorType } : {},
      order: { createdAt: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }
}

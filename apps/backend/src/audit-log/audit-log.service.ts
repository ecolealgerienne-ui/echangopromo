import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
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
}

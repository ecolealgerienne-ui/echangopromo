import { IsEnum, IsOptional } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import { AuditActorType } from '../entities/audit-log.entity';

export class ListAuditLogQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsEnum(AuditActorType)
  actorType?: AuditActorType;
}

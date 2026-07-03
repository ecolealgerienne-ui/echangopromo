import { IsOptional, IsUUID } from 'class-validator';

export class AssignZoneDto {
  @IsOptional()
  @IsUUID()
  zoneId?: string | null;
}

import { IsUUID } from 'class-validator';

export class TransferZoneDto {
  @IsUUID()
  zoneId: string;

  @IsUUID()
  fromAgentId: string;

  @IsUUID()
  toAgentId: string;
}

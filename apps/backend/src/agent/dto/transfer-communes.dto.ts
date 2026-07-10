import { IsArray, IsUUID } from 'class-validator';

export class TransferCommunesDto {
  @IsArray()
  @IsUUID(undefined, { each: true })
  communeIds: string[];

  @IsUUID()
  fromAgentId: string;

  @IsUUID()
  toAgentId: string;
}

import { IsUUID } from 'class-validator';

export class CreateReportDto {
  @IsUUID()
  promoId: string;
}

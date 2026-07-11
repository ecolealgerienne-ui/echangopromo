import { IsEnum, IsUUID } from 'class-validator';
import { ReportReason } from '../entities/report.entity';

export class CreateReportDto {
  @IsUUID()
  promoId: string;

  @IsEnum(ReportReason)
  reason: ReportReason;
}

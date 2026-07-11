import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { STRICT_THROTTLE } from '../common/throttle';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { CreateReportDto } from './dto/create-report.dto';
import { ReportService } from './report.service';

@Controller('report')
export class ReportController {
  constructor(private readonly reportService: ReportService) {}

  /**
   * Endpoint public protégé uniquement par un `X-Device-Id` déclaratif
   * jamais vérifié serveur — sans rate limiting par IP, 3 requêtes suffisent
   * à faire masquer la promo d'un concurrent (specs §5.4, audit sécurité).
   */
  @Throttle(STRICT_THROTTLE)
  @Post()
  async create(@Body() dto: CreateReportDto, @DeviceId() deviceId: string) {
    await this.reportService.createReport(dto.promoId, deviceId, dto.reason);
    return { ok: true };
  }
}

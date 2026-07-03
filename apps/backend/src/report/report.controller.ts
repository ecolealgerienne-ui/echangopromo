import { Body, Controller, Post } from '@nestjs/common';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { CreateReportDto } from './dto/create-report.dto';
import { ReportService } from './report.service';

@Controller('report')
export class ReportController {
  constructor(private readonly reportService: ReportService) {}

  @Post()
  async create(@Body() dto: CreateReportDto, @DeviceId() deviceId: string) {
    await this.reportService.createReport(dto.promoId, deviceId);
    return { ok: true };
  }
}

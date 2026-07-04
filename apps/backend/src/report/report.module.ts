import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Promo } from '../promo/entities/promo.entity';
import { PromoModule } from '../promo/promo.module';
import { ReportController } from './report.controller';
import { ReportService } from './report.service';
import { Report } from './entities/report.entity';

@Module({
  imports: [TypeOrmModule.forFeature([Report, Promo]), PromoModule],
  controllers: [ReportController],
  providers: [ReportService],
  exports: [ReportService],
})
export class ReportModule {}

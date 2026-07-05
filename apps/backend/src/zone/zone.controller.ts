import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { PaginationQueryDto } from '../common/pagination/pagination-query.dto';
import { CreateZoneDto } from './dto/create-zone.dto';
import { UpdateZoneDto } from './dto/update-zone.dto';
import { ZoneService } from './zone.service';

/** Gestion des zones opérationnelles — réservée à l'admin (specs §3.4). */
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('admin')
@Controller('zone')
export class ZoneController {
  constructor(private readonly zoneService: ZoneService) {}

  @Post()
  async create(@Body() dto: CreateZoneDto) {
    return this.zoneService.create(dto);
  }

  @Get()
  async list(@Query() query: PaginationQueryDto) {
    return this.zoneService.findAll(query.page, query.limit);
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() dto: UpdateZoneDto) {
    return this.zoneService.update(id, dto);
  }
}

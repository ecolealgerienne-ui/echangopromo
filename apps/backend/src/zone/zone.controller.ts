import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
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
  async list() {
    return this.zoneService.findAll();
  }

  @Patch(':id')
  async update(@Param('id') id: string, @Body() dto: UpdateZoneDto) {
    return this.zoneService.update(id, dto);
  }
}

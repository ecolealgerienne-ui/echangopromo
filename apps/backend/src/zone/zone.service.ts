import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { CreateZoneDto } from './dto/create-zone.dto';
import { UpdateZoneDto } from './dto/update-zone.dto';
import { Zone } from './entities/zone.entity';

@Injectable()
export class ZoneService {
  constructor(
    @InjectRepository(Zone) private readonly zones: Repository<Zone>,
  ) {}

  async create(dto: CreateZoneDto): Promise<Zone> {
    return this.zones.save(
      this.zones.create({ ...dto, description: dto.description ?? null }),
    );
  }

  async findAll(): Promise<Zone[]> {
    return this.zones.find();
  }

  async findByIdOrFail(id: string): Promise<Zone> {
    const zone = await this.zones.findOne({ where: { id } });
    if (!zone) {
      throw new NotFoundException('Zone introuvable');
    }
    return zone;
  }

  async update(id: string, dto: UpdateZoneDto): Promise<Zone> {
    const zone = await this.findByIdOrFail(id);
    Object.assign(zone, dto);
    return this.zones.save(zone);
  }
}

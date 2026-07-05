import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { NotFoundAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
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

  async findAll(page: number, limit: number): Promise<PaginatedResult<Zone>> {
    const [items, total] = await this.zones.findAndCount({
      order: { nom: 'ASC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  async findByIdOrFail(id: string): Promise<Zone> {
    const zone = await this.zones.findOne({ where: { id } });
    if (!zone) {
      throw new NotFoundAppException(ErrorCode.ZONE_NOT_FOUND, 'Zone introuvable');
    }
    return zone;
  }

  async update(id: string, dto: UpdateZoneDto): Promise<Zone> {
    const zone = await this.findByIdOrFail(id);
    Object.assign(zone, dto);
    return this.zones.save(zone);
  }
}

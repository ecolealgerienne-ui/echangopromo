import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { NotFoundAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { PaginatedResult, toPaginatedResult } from '../common/pagination/paginated-result';
import { Commune } from './entities/commune.entity';

@Injectable()
export class CommuneService {
  constructor(
    @InjectRepository(Commune) private readonly communes: Repository<Commune>,
  ) {}

  async findAll(
    wilaya: string | undefined,
    page: number,
    limit: number,
  ): Promise<PaginatedResult<Commune>> {
    const [items, total] = await this.communes.findAndCount({
      where: wilaya ? { wilaya } : {},
      order: { wilaya: 'ASC', nom: 'ASC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return toPaginatedResult(items, total, page, limit);
  }

  async findByIdOrFail(id: string): Promise<Commune> {
    const commune = await this.communes.findOne({ where: { id } });
    if (!commune) {
      throw new NotFoundAppException(ErrorCode.COMMUNE_NOT_FOUND, 'Commune introuvable');
    }
    return commune;
  }
}

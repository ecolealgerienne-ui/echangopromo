import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { NotFoundAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { Commune } from './entities/commune.entity';

@Injectable()
export class CommuneService {
  constructor(
    @InjectRepository(Commune) private readonly communes: Repository<Commune>,
  ) {}

  async findAll(wilaya?: string): Promise<Commune[]> {
    return this.communes.find(wilaya ? { where: { wilaya } } : {});
  }

  async findByIdOrFail(id: string): Promise<Commune> {
    const commune = await this.communes.findOne({ where: { id } });
    if (!commune) {
      throw new NotFoundAppException(ErrorCode.COMMUNE_NOT_FOUND, 'Commune introuvable');
    }
    return commune;
  }
}

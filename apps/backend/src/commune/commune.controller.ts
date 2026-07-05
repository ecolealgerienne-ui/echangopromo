import { Controller, Get, Query } from '@nestjs/common';
import { CommuneService } from './commune.service';
import { ListCommuneQueryDto } from './dto/list-commune-query.dto';

@Controller('commune')
export class CommuneController {
  constructor(private readonly communeService: CommuneService) {}

  @Get()
  async list(@Query() query: ListCommuneQueryDto) {
    return this.communeService.findAll(query.wilaya, query.page, query.limit);
  }
}

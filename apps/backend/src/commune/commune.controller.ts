import { Controller, Get, Query } from '@nestjs/common';
import { CommuneService } from './commune.service';

@Controller('commune')
export class CommuneController {
  constructor(private readonly communeService: CommuneService) {}

  @Get()
  async list(@Query('wilaya') wilaya?: string) {
    return this.communeService.findAll(wilaya);
  }
}

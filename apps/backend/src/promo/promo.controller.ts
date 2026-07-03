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
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { PromoService } from './promo.service';

@Controller('promo')
export class PromoController {
  constructor(private readonly promoService: PromoService) {}

  @Get()
  async list(@Query() query: ListPromoQueryDto) {
    return this.promoService.findActiveForClient(query);
  }

  @Get(':id')
  async detail(@Param('id') id: string, @DeviceId() deviceId: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.promoService.recordView(id, deviceId);
    return promo;
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Post()
  async create(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreatePromoDto,
  ) {
    return this.promoService.create(user.sub, dto);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/all')
  async mine(@CurrentUser() user: AuthTokenPayload) {
    const promos = await this.promoService.listByCommercant(user.sub);
    const viewCounts = await this.promoService.getViewCounts(
      promos.map((p) => p.id),
    );
    return promos.map((promo) => ({
      ...promo,
      viewCount: viewCounts[promo.id] ?? 0,
    }));
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Post('agent/:commercantId')
  async createByAgent(
    @Param('commercantId') commercantId: string,
    @Body() dto: CreatePromoDto,
  ) {
    return this.promoService.create(commercantId, dto);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('agent')
  @Patch(':id')
  async update(@Param('id') id: string, @Body() dto: UpdatePromoDto) {
    return this.promoService.update(id, dto);
  }
}

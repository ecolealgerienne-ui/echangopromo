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
import { StorageService } from '../storage/storage.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { ListPromoQueryDto } from './dto/list-promo-query.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { Promo } from './entities/promo.entity';
import { PromoService } from './promo.service';

@Controller('promo')
export class PromoController {
  constructor(
    private readonly promoService: PromoService,
    private readonly storageService: StorageService,
  ) {}

  /** Ajoute l'URL publique résolue à partir de la clé S3 (specs §5.8) — le
   * client n'a jamais accès à la clé brute, seulement à l'URL lisible. */
  private withPhotoUrl(promo: Promo) {
    return {
      ...promo,
      photoUrl: this.storageService.buildPublicUrl(promo.photoKey),
    };
  }

  @Get()
  async list(@Query() query: ListPromoQueryDto) {
    const promos = await this.promoService.findActiveForClient(query);
    return promos.map((promo) => this.withPhotoUrl(promo));
  }

  @Get(':id')
  async detail(@Param('id') id: string, @DeviceId() deviceId: string) {
    const promo = await this.promoService.findByIdOrFail(id);
    await this.promoService.recordView(id, deviceId);
    return this.withPhotoUrl(promo);
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
      ...this.withPhotoUrl(promo),
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

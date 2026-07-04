import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { CreatePresignedUploadDto } from './dto/create-presigned-upload.dto';
import { StorageService } from './storage.service';

/**
 * Compression/redimensionnement obligatoire côté app AVANT upload (specs
 * §5.8) — cet endpoint ne fait que délivrer une URL pré-signée S3, il ne
 * traite pas l'image.
 */
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('commercant', 'agent')
@Controller('storage')
export class StorageController {
  constructor(private readonly storageService: StorageService) {}

  @Post('presigned-upload')
  async presignedUpload(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: CreatePresignedUploadDto,
  ) {
    const extension = dto.contentType === 'image/png' ? 'png' : 'jpg';
    const key = this.storageService.buildKey(user.sub, extension);
    return this.storageService.createPresignedUpload(key, dto.contentType);
  }
}

import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { AuthService } from '../auth/auth.service';
import type { AuthTokenPayload } from '../auth/role';
import { SENSITIVE_ACTION_THROTTLE, STRICT_THROTTLE } from '../common/throttle';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { StorageService } from '../storage/storage.service';
import { CommercantService } from './commercant.service';
import { ClaimCommercantDto } from './dto/claim-commercant.dto';
import { Commercant } from './entities/commercant.entity';
import { LoginCommercantDto } from './dto/login-commercant.dto';
import { RegisterCommercantDto } from './dto/register-commercant.dto';
import { RequestRegistreVerificationDto } from './dto/request-registre-verification.dto';
import { UpdateCommercantDto } from './dto/update-commercant.dto';

@Controller('commercant')
export class CommercantController {
  constructor(
    private readonly commercantService: CommercantService,
    private readonly authService: AuthService,
    private readonly storageService: StorageService,
  ) {}

  private photoUrl(commercant: Commercant): string | null {
    return commercant.photoKey
      ? this.storageService.buildPublicUrl(commercant.photoKey)
      : null;
  }

  @Throttle(STRICT_THROTTLE)
  @Post('register')
  async register(@Body() dto: RegisterCommercantDto) {
    const commercant = await this.commercantService.selfRegister(dto);
    return {
      accessToken: this.authService.issueToken(
        commercant.id,
        'commercant',
        commercant.tokenVersion,
      ),
    };
  }

  /** Active un compte créé par un agent (ou réinitialisé par l'admin) — pas d'OTP. */
  @Throttle(STRICT_THROTTLE)
  @Post('claim')
  async claim(@Body() dto: ClaimCommercantDto) {
    const commercant = await this.commercantService.claim(dto);
    return {
      accessToken: this.authService.issueToken(
        commercant.id,
        'commercant',
        commercant.tokenVersion,
      ),
    };
  }

  @Throttle(STRICT_THROTTLE)
  @Post('login')
  async login(@Body() dto: LoginCommercantDto) {
    const commercant = await this.commercantService.login(
      dto.telephone,
      dto.pin,
    );
    return {
      accessToken: this.authService.issueToken(
        commercant.id,
        'commercant',
        commercant.tokenVersion,
      ),
    };
  }

  /** Fiche publique consultée depuis le détail d'une promo (specs §3.1). */
  @Get(':id/public')
  async publicProfile(@Param('id') id: string, @DeviceId() deviceId: string) {
    const commercant = await this.commercantService.findPublicProfile(id);
    await this.commercantService.recordProfileView(id, deviceId);
    return {
      id: commercant.id,
      nom: commercant.nom,
      adresse: commercant.adresse,
      categorie: commercant.categorie,
      communeId: commercant.communeId,
      // Ajouté 2026-07-12 : le client a besoin d'appeler le commerçant
      // depuis la fiche promo (tap-pour-appeler), pas seulement de voir son
      // adresse — jusqu'ici omis de cette réponse publique (contrairement à
      // `toMeJson`), pas une décision de confidentialité documentée.
      telephone: commercant.telephone,
      photoUrl: this.photoUrl(commercant),
      latitude: commercant.latitude,
      longitude: commercant.longitude,
    };
  }

  private toMeJson(commercant: Commercant) {
    return {
      id: commercant.id,
      telephone: commercant.telephone,
      nom: commercant.nom,
      adresse: commercant.adresse,
      categorie: commercant.categorie,
      communeId: commercant.communeId,
      accountState: commercant.accountState,
      originVerification: commercant.originVerification,
      registreStatus: commercant.registreStatus,
      profilePendingReview: commercant.profilePendingReview,
      photoUrl: this.photoUrl(commercant),
      latitude: commercant.latitude,
      longitude: commercant.longitude,
      createdAt: commercant.createdAt,
    };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    const commercant = await this.commercantService.findByIdOrFail(user.sub);
    return this.toMeJson(commercant);
  }

  /** Édition du profil par le commerçant lui-même — téléphone non modifiable ici. */
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Patch('me')
  async updateMe(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: UpdateCommercantDto,
  ) {
    const commercant = await this.commercantService.updateProfile(user.sub, dto);
    return this.toMeJson(commercant);
  }

  /**
   * Suppression de compte par le commerçant lui-même — soft delete
   * uniquement (`deletedAt`), jamais de suppression physique.
   */
  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Delete('me')
  async deleteMe(@CurrentUser() user: AuthTokenPayload): Promise<{ ok: true }> {
    await this.commercantService.deleteAccount(user.sub);
    return { ok: true };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/dashboard')
  async dashboard(@CurrentUser() user: AuthTokenPayload) {
    return this.commercantService.getDashboardStats(user.sub);
  }

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Post('me/registre')
  async requestRegistre(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: RequestRegistreVerificationDto,
  ) {
    await this.commercantService.requestRegistreVerification(
      user.sub,
      dto.registreKey,
    );
    return { ok: true };
  }
}

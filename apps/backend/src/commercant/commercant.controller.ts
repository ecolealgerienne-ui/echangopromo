import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { OtpPurpose } from '../auth/entities/otp-code.entity';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { AuthService } from '../auth/auth.service';
import type { AuthTokenPayload } from '../auth/role';
import { DeviceId } from '../common/decorators/device-id.decorator';
import { CommercantService } from './commercant.service';
import { ConfirmPhoneDto } from './dto/confirm-phone.dto';
import { ForgotPinConfirmDto, ForgotPinRequestDto } from './dto/forgot-pin.dto';
import { LoginCommercantDto } from './dto/login-commercant.dto';
import { RegisterCommercantDto } from './dto/register-commercant.dto';
import { RequestRegistreVerificationDto } from './dto/request-registre-verification.dto';

@Controller('commercant')
export class CommercantController {
  constructor(
    private readonly commercantService: CommercantService,
    private readonly authService: AuthService,
  ) {}

  @Post('register')
  async register(@Body() dto: RegisterCommercantDto) {
    return this.commercantService.selfRegister(dto);
  }

  @Post('confirm-inscription')
  async confirmInscription(@Body() dto: ConfirmPhoneDto) {
    const commercant = await this.commercantService.confirmPhoneAndSetPin(
      OtpPurpose.INSCRIPTION,
      dto,
    );
    return {
      accessToken: this.authService.issueToken(commercant.id, 'commercant'),
    };
  }

  @Post('confirm-revendication')
  async confirmRevendication(@Body() dto: ConfirmPhoneDto) {
    const commercant = await this.commercantService.confirmPhoneAndSetPin(
      OtpPurpose.REVENDICATION,
      dto,
    );
    return {
      accessToken: this.authService.issueToken(commercant.id, 'commercant'),
    };
  }

  @Post('login')
  async login(@Body() dto: LoginCommercantDto) {
    const commercant = await this.commercantService.login(
      dto.telephone,
      dto.pin,
    );
    return {
      accessToken: this.authService.issueToken(commercant.id, 'commercant'),
    };
  }

  @Post('forgot-pin/request')
  async forgotPinRequest(@Body() dto: ForgotPinRequestDto) {
    await this.commercantService.requestForgotPin(dto.telephone);
    return { ok: true };
  }

  @Post('forgot-pin/confirm')
  async forgotPinConfirm(@Body() dto: ForgotPinConfirmDto) {
    await this.commercantService.confirmForgotPin(
      dto.telephone,
      dto.code,
      dto.newPin,
    );
    return { ok: true };
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
    };
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me')
  async me(@CurrentUser() user: AuthTokenPayload) {
    return this.commercantService.findByIdOrFail(user.sub);
  }

  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('commercant')
  @Get('me/dashboard')
  async dashboard(@CurrentUser() user: AuthTokenPayload) {
    return this.commercantService.getDashboardStats(user.sub);
  }

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

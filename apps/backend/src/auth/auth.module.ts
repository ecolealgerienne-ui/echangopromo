import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule, JwtModuleOptions } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { RolesGuard } from './guards/roles.guard';

@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService): JwtModuleOptions => ({
        secret: config.get<string>('JWT_SECRET'),
        // `expiresIn` accepte une durée libre ('30d') non représentable par le
        // type `StringValue` trop strict de la lib `ms` — cast nécessaire.
        signOptions: {
          expiresIn: config.get<string>(
            'JWT_EXPIRES_IN',
            '30d',
          ) as unknown as number,
        },
      }),
    }),
  ],
  providers: [AuthService, JwtAuthGuard, RolesGuard],
  exports: [AuthService, JwtModule, JwtAuthGuard, RolesGuard],
})
export class AuthModule {}

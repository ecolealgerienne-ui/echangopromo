import {
  Body,
  Controller,
  Post,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { Roles } from '../auth/decorators/roles.decorator';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import type { AuthTokenPayload } from '../auth/role';
import { BadRequestAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { SENSITIVE_ACTION_THROTTLE } from '../common/throttle';
import { UploadPhotoDto } from './dto/upload-photo.dto';
import { MAX_UPLOAD_BYTES, StorageService } from './storage.service';

/**
 * Upload proxifié par le backend plutôt qu'une POST policy S3 pré-signée :
 * OVH (le S3 utilisé en prod) renvoie `501 Not Implemented — "POST Object
 * is disabled on this deployment"` sur cette API, découvert au premier
 * test réel post-déploiement. Le fichier transite donc par notre backend,
 * qui valide taille et format (magic bytes) AVANT tout envoi à S3, plutôt
 * que de compter sur une contrainte imposée par S3 lui-même.
 *
 * Limite Multer volontairement plus haute (×4) que `MAX_UPLOAD_BYTES` : un
 * simple filet de sécurité mémoire contre un payload extrême, la vraie
 * règle métier (500 Ko, voir `MAX_UPLOAD_BYTES` — le commentaire disait
 * encore « 5 Mo », valeur abandonnée le 2026-07-12) est appliquée
 * explicitement dans `StorageService` pour renvoyer une erreur applicative
 * propre (`AppException`) plutôt qu'une erreur Multer brute.
 *
 * Au-delà du filet Multer, en revanche, la requête est coupée avant
 * d'atteindre `StorageService` : c'est `AllExceptionsFilter` qui rattache le
 * `413` à `STORAGE_FILE_TOO_LARGE`, pour que le mobile affiche la même chose
 * dans les deux cas.
 */
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('commercant', 'agent', 'admin')
@Controller('storage')
export class StorageController {
  constructor(private readonly storageService: StorageService) {}

  @Throttle(SENSITIVE_ACTION_THROTTLE)
  @Post('upload')
  @UseInterceptors(
    FileInterceptor('file', { limits: { fileSize: MAX_UPLOAD_BYTES * 4 } }),
  )
  async upload(
    @CurrentUser() user: AuthTokenPayload,
    @Body() dto: UploadPhotoDto,
    @UploadedFile() file: Express.Multer.File,
  ): Promise<{ key: string }> {
    if (!file) {
      throw new BadRequestAppException(
        ErrorCode.STORAGE_INVALID_IMAGE,
        'Aucun fichier reçu.',
      );
    }
    // Le flux registre est un self-service commerçant (`POST
    // /commercant/me/registre` est `@Roles('commercant')` exclusivement) —
    // aucun endpoint n'exploite un upload `registre` fait par un agent,
    // restreint explicitement plutôt que de compter sur cette absence
    // d'usage (audit sécurité 2026-07-11).
    if (dto.purpose === 'registre' && user.role !== 'commercant') {
      throw new BadRequestAppException(
        ErrorCode.STORAGE_PURPOSE_NOT_ALLOWED,
        "Ce type d'upload est réservé au commerçant.",
      );
    }
    // Le visuel du bandeau d'accueil n'est composé que par l'admin
    // (`AdminHighlightController`) — restreint ici explicitement plutôt que
    // de laisser un commerçant écrire dans ce préfixe, même sans endpoint
    // pour l'exploiter (même raisonnement que `registre` ci-dessus).
    if (dto.purpose === 'highlight' && user.role !== 'admin') {
      throw new BadRequestAppException(
        ErrorCode.STORAGE_PURPOSE_NOT_ALLOWED,
        "Ce type d'upload est réservé à l'administrateur.",
      );
    }
    const folder =
      dto.purpose === 'commercant'
        ? 'commercant-photos'
        : dto.purpose === 'registre'
          ? 'registre-documents'
          : dto.purpose === 'highlight'
            ? 'highlight-images'
            : 'promo-photos';
    const key = await this.storageService.uploadPhoto(
      user.sub,
      file.buffer,
      folder,
    );
    return { key };
  }
}

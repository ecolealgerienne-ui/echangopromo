import { DeleteObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { BadRequestAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { detectImageFormat } from './image-signature';

/**
 * Limite haute vu la compression obligatoire côté app avant upload (max
 * ~1200px, JPEG qualité ~80, specs §5.8) — sert de garde-fou contre un
 * upload arbitrairement volumineux (audit sécurité).
 */
export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

@Injectable()
export class StorageService {
  private readonly client: S3Client;
  private readonly bucket: string;
  private readonly cdnBaseUrl: string | undefined;

  constructor(private readonly configService: ConfigService) {
    this.bucket = this.configService.get<string>('S3_BUCKET', '');
    this.cdnBaseUrl =
      this.configService.get<string>('S3_CDN_BASE_URL') || undefined;

    this.client = new S3Client({
      region: this.configService.get<string>('S3_REGION', 'gra'),
      endpoint: this.configService.get<string>('S3_ENDPOINT'),
      // Requis par la plupart des S3 non-AWS (OVH, MinIO...) : sans ça, le
      // SDK génère des URL virtual-hosted-style (bucket en sous-domaine) que
      // ces fournisseurs ne servent pas.
      forcePathStyle: true,
      credentials: {
        accessKeyId: this.configService.get<string>('S3_ACCESS_KEY_ID', ''),
        secretAccessKey: this.configService.get<string>(
          'S3_SECRET_ACCESS_KEY',
          '',
        ),
      },
    });
  }

  /**
   * Structure de bucket prévue pour le nettoyage automatique (specs §5.8) —
   * uniquement les photos de promo (`promo-photos/`) sont purgées après
   * `IMAGE_RETENTION_DAYS` (voir `PromoService.purgeOldPhotosCron`) ; la
   * photo de commerce (`commercant-photos/`) est permanente, d'où le préfixe
   * distinct.
   */
  buildKey(
    commercantId: string,
    extension: string,
    folder: 'promo-photos' | 'commercant-photos' = 'promo-photos',
  ): string {
    return `${folder}/${commercantId}/${randomUUID()}.${extension}`;
  }

  /**
   * Upload proxifié par le backend (pas de POST policy S3 pré-signée) : OVH
   * (le S3 utilisé en prod) renvoie `501 Not Implemented — "POST Object is
   * disabled on this deployment"` sur cette API — découvert au premier test
   * réel post-déploiement, cette API n'est donc pas portable entre
   * fournisseurs S3. Taille et format (magic bytes) sont validés ici, sur
   * les octets déjà en mémoire, AVANT tout envoi à S3 via `PutObject`
   * (universellement supporté) — remplace l'ancienne vérification a
   * posteriori (`assertValidImage`, qui refaisait un `GetObject` après
   * upload) devenue inutile : un fichier invalide n'atteint plus jamais S3.
   */
  async uploadPhoto(
    commercantId: string,
    buffer: Buffer,
    folder: 'promo-photos' | 'commercant-photos' = 'promo-photos',
  ): Promise<string> {
    if (buffer.length > MAX_UPLOAD_BYTES) {
      throw new BadRequestAppException(
        ErrorCode.STORAGE_FILE_TOO_LARGE,
        'Le fichier dépasse la taille maximale autorisée (5 Mo).',
      );
    }
    const format = detectImageFormat(buffer);
    if (!format) {
      throw new BadRequestAppException(
        ErrorCode.STORAGE_INVALID_IMAGE,
        "Le fichier envoyé n'est pas une image valide (jpeg/png/webp)",
      );
    }

    const extension = format === 'jpeg' ? 'jpg' : format;
    const key = this.buildKey(commercantId, extension, folder);
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: buffer,
        ContentType: `image/${format}`,
      }),
    );
    return key;
  }

  buildPublicUrl(key: string): string {
    if (this.cdnBaseUrl) {
      return `${this.cdnBaseUrl.replace(/\/$/, '')}/${key}`;
    }
    return `${this.configService.get<string>('S3_ENDPOINT', '')}/${this.bucket}/${key}`;
  }

  async deleteObject(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }
}

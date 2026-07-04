import { DeleteObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';

const PRESIGNED_URL_TTL_SECONDS = 5 * 60;

/**
 * Limite haute généreuse vu la compression obligatoire côté app avant
 * upload (max ~1200px, JPEG qualité ~80, specs §5.8) — sert uniquement de
 * garde-fou contre un upload arbitrairement volumineux (audit sécurité :
 * un PUT pré-signé simple n'imposait aucune limite de taille).
 */
const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

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
   * POST policy S3 (pas un simple PUT pré-signé) : `content-length-range`
   * est une contrainte appliquée par S3 lui-même, contrairement à un PUT où
   * le `Content-Type` déclaré à la signature n'engage à rien lors de
   * l'upload réel.
   */
  async createPresignedUpload(
    key: string,
    contentType: string,
  ): Promise<{ url: string; fields: Record<string, string>; key: string }> {
    const { url, fields } = await createPresignedPost(this.client, {
      Bucket: this.bucket,
      Key: key,
      Conditions: [
        ['content-length-range', 0, MAX_UPLOAD_BYTES],
        { 'Content-Type': contentType },
      ],
      Fields: { 'Content-Type': contentType },
      Expires: PRESIGNED_URL_TTL_SECONDS,
    });
    return { url, fields, key };
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

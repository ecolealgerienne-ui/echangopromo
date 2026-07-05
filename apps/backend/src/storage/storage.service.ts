import {
  DeleteObjectCommand,
  GetObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { BadRequestAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { hasValidImageSignature } from './image-signature';

const PRESIGNED_URL_TTL_SECONDS = 5 * 60;

/** 12 octets suffisent pour distinguer les signatures JPEG/PNG/WEBP. */
const MAGIC_BYTES_RANGE = 'bytes=0-11';

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

  /**
   * Vérifie a posteriori que le fichier uploadé est réellement une image
   * (magic bytes) — le `Content-Type` déclaré à la signature (§ci-dessus)
   * n'engage à rien sur le contenu réel envoyé lors du POST (audit V1 §7).
   * Supprime le fichier et lève une erreur si la signature ne correspond à
   * aucun format supporté (jpeg/png/webp).
   */
  async assertValidImage(key: string): Promise<void> {
    const response = await this.client.send(
      new GetObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Range: MAGIC_BYTES_RANGE,
      }),
    );
    const bytes = await this.readBody(response.Body);
    if (!hasValidImageSignature(bytes)) {
      await this.deleteObject(key);
      throw new BadRequestAppException(
        ErrorCode.STORAGE_INVALID_IMAGE,
        "Le fichier envoyé n'est pas une image valide (jpeg/png/webp)",
      );
    }
  }

  private async readBody(body: unknown): Promise<Buffer> {
    const chunks: Buffer[] = [];
    for await (const chunk of body as AsyncIterable<Buffer>) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
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

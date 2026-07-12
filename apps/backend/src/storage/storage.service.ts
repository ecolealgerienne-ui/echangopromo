import {
  DeleteObjectCommand,
  GetObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { BadRequestAppException } from '../common/errors/app-exception';
import { ErrorCode } from '../common/errors/error-code.enum';
import { detectImageFormat } from './image-signature';

/**
 * Le client cible ~250 Ko après compression par paliers (`StorageApi.
 * _compress`, mobile) — ce plafond n'est qu'un filet de sécurité serveur,
 * pas l'objectif : 5 Mo (valeur d'origine) était beaucoup trop généreux
 * pour le marché algérien (coût data, couverture réseau variable à Djelfa),
 * decision 2026-07-12. Marge au-dessus de la cible client pour ne jamais
 * rejeter une compression légitime qui atterrit un peu plus haut sur une
 * image très texturée.
 */
export const MAX_UPLOAD_BYTES = 500 * 1024;

export type UploadFolder = 'promo-photos' | 'commercant-photos' | 'registre-documents';

/**
 * Le registre de commerce est un justificatif d'identité professionnelle,
 * pas une photo destinée au public (contrairement aux deux autres dossiers)
 * — ACL privée + URL pré-signée à la demande (`getPresignedUrl`), plutôt que
 * `public-read` (audit sécurité 2026-07-11 : la clé S3 fuitait déjà côté
 * agent, une ACL publique la rendait exploitable sans même cette fuite).
 */
const PRIVATE_FOLDERS: readonly UploadFolder[] = ['registre-documents'];

/**
 * Régénérée à chaque `GET /admin/commercant`, jamais stockée telle quelle.
 * 15 min plutôt qu'une durée très courte : l'URL est passée à l'écran détail
 * via la navigation (`extra: item`, pas un nouveau fetch), le temps de
 * consultation admin doit tenir dans cette fenêtre sans re-signer.
 */
const PRESIGNED_URL_TTL_SECONDS = 15 * 60;

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
   * photo de commerce (`commercant-photos/`) et le registre de commerce
   * (`registre-documents/`, pièce justificative conservée pour traçabilité
   * de la validation admin) sont permanents, d'où le préfixe distinct.
   */
  buildKey(
    commercantId: string,
    extension: string,
    folder: UploadFolder = 'promo-photos',
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
    folder: UploadFolder = 'promo-photos',
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
        // OVH n'implémente ni les bucket policies (NotImplemented sur
        // PutBucketPolicy) ni les requêtes anonymes en style path (400 sur
        // GET sans ACL) — seul l'ACL par objet `public-read` (testé et
        // confirmé) rend la photo accessible via `buildPublicUrl` (style
        // virtual-hosted, voir plus bas). `registre-documents/` reste privé
        // (voir `PRIVATE_FOLDERS`) : consulté uniquement via
        // `getPresignedUrl`, jamais via une URL publique permanente.
        ACL: PRIVATE_FOLDERS.includes(folder) ? 'private' : 'public-read',
      }),
    );
    return key;
  }

  /**
   * OVH rejette les requêtes anonymes en style "path" (`endpoint/bucket/clé`)
   * avec `400 InvalidRequest — "Not S3 request"` — découvert au premier test
   * réel d'affichage de photo. Seul le style "virtual-hosted"
   * (`bucket.endpoint/clé`) fonctionne pour un accès public non signé.
   * `forcePathStyle: true` sur le client S3 (voir constructeur) reste
   * nécessaire pour les opérations authentifiées (PUT/DELETE, compatibles
   * MinIO en dev local) — seule cette URL construite pour un accès public
   * anonyme doit basculer en virtual-hosted, activé via
   * `S3_PUBLIC_URL_VIRTUAL_HOSTED=true` (mis à `true` uniquement pour OVH
   * en prod, laissé à `false` par défaut pour MinIO en dev local).
   */
  buildPublicUrl(key: string): string {
    if (this.cdnBaseUrl) {
      return `${this.cdnBaseUrl.replace(/\/$/, '')}/${key}`;
    }
    const endpoint = this.configService.get<string>('S3_ENDPOINT', '');
    const useVirtualHostedStyle =
      this.configService.get<string>('S3_PUBLIC_URL_VIRTUAL_HOSTED', 'false') === 'true';
    if (useVirtualHostedStyle) {
      const host = endpoint.replace(/^https?:\/\//, '').replace(/\/$/, '');
      return `https://${this.bucket}.${host}/${key}`;
    }
    return `${endpoint}/${this.bucket}/${key}`;
  }

  /**
   * URL temporaire signée pour un objet privé (`registre-documents/`) —
   * appelée à la demande par un admin authentifié uniquement (jamais
   * stockée), contrairement à `buildPublicUrl` qui pointe vers un objet
   * `public-read` permanent.
   */
  async getPresignedUrl(key: string): Promise<string> {
    return getSignedUrl(
      this.client,
      new GetObjectCommand({ Bucket: this.bucket, Key: key }),
      { expiresIn: PRESIGNED_URL_TTL_SECONDS },
    );
  }

  async deleteObject(key: string): Promise<void> {
    await this.client.send(
      new DeleteObjectCommand({ Bucket: this.bucket, Key: key }),
    );
  }
}

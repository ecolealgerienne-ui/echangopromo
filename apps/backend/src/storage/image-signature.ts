/**
 * Détection de type par magic bytes (jpeg/png/webp) — fonction pure,
 * testable sans mock S3 (première pierre de couverture de tests backend,
 * audit V1 §6).
 */
export type ImageFormat = 'jpeg' | 'png' | 'webp';

export function detectImageFormat(bytes: Buffer): ImageFormat | null {
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (isJpeg) return 'jpeg';

  const isPng =
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (isPng) return 'png';

  const isWebp =
    bytes.subarray(0, 4).toString('ascii') === 'RIFF' &&
    bytes.subarray(8, 12).toString('ascii') === 'WEBP';
  if (isWebp) return 'webp';

  return null;
}

export function hasValidImageSignature(bytes: Buffer): boolean {
  return detectImageFormat(bytes) !== null;
}

/**
 * Détection de type par magic bytes (jpeg/png/webp) — fonction pure,
 * extraite de `StorageService.assertValidImage` pour être testable sans
 * mock S3 (première pierre de couverture de tests backend, audit V1 §6).
 */
export function hasValidImageSignature(bytes: Buffer): boolean {
  const isJpeg = bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  const isPng =
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  const isWebp =
    bytes.subarray(0, 4).toString('ascii') === 'RIFF' &&
    bytes.subarray(8, 12).toString('ascii') === 'WEBP';
  return isJpeg || isPng || isWebp;
}

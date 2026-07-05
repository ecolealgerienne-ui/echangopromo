import { hasValidImageSignature } from './image-signature';

describe('hasValidImageSignature', () => {
  it('accepte une signature JPEG', () => {
    expect(hasValidImageSignature(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).toBe(true);
  });

  it('accepte une signature PNG', () => {
    expect(
      hasValidImageSignature(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
    ).toBe(true);
  });

  it('accepte une signature WEBP', () => {
    const bytes = Buffer.concat([
      Buffer.from('RIFF', 'ascii'),
      Buffer.from([0, 0, 0, 0]),
      Buffer.from('WEBP', 'ascii'),
    ]);
    expect(hasValidImageSignature(bytes)).toBe(true);
  });

  it("rejette un fichier qui n'est pas une image (ex: exécutable renommé .jpg)", () => {
    expect(hasValidImageSignature(Buffer.from('MZ\x90\x00', 'ascii'))).toBe(false);
  });

  it('rejette un buffer vide', () => {
    expect(hasValidImageSignature(Buffer.alloc(0))).toBe(false);
  });
});

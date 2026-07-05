import { ConfigService } from '@nestjs/config';
import { AppLinksController } from './app-links.controller';

function configWith(values: Record<string, string>): ConfigService {
  return {
    get: (key: string, defaultValue?: string) => values[key] ?? defaultValue,
  } as ConfigService;
}

function fakeResponse() {
  return {
    redirectedTo: undefined as string | number | undefined,
    htmlSent: undefined as string | undefined,
    redirect(status: number, url: string) {
      this.redirectedTo = `${status} ${url}`;
    },
    status() {
      return this;
    },
    type() {
      return this;
    },
    send(body: string) {
      this.htmlSent = body;
    },
  };
}

describe('AppLinksController', () => {
  describe('assetlinks', () => {
    it('retourne un tableau vide tant que le package/l\'empreinte ne sont pas configurés', () => {
      const controller = new AppLinksController(configWith({}));
      expect(controller.assetlinks()).toEqual([]);
    });

    it('retourne la déclaration Digital Asset Links une fois configuré', () => {
      const controller = new AppLinksController(
        configWith({
          ANDROID_PACKAGE_NAME: 'com.echango.promo',
          ANDROID_SHA256_CERT_FINGERPRINT: 'AA:BB',
        }),
      );
      expect(controller.assetlinks()).toEqual([
        {
          relation: ['delegate_permission/common.handle_all_urls'],
          target: {
            namespace: 'android_app',
            package_name: 'com.echango.promo',
            sha256_cert_fingerprints: ['AA:BB'],
          },
        },
      ]);
    });
  });

  describe('appleAppSiteAssociation', () => {
    it('retourne une structure vide (mais valide) tant que team/bundle ne sont pas configurés', () => {
      const controller = new AppLinksController(configWith({}));
      expect(controller.appleAppSiteAssociation()).toEqual({
        applinks: { apps: [], details: [] },
      });
    });

    it('retourne le appID une fois configuré', () => {
      const controller = new AppLinksController(
        configWith({ IOS_TEAM_ID: 'TEAM123', IOS_BUNDLE_ID: 'com.echango.promo' }),
      );
      expect(controller.appleAppSiteAssociation()).toEqual({
        applinks: {
          apps: [],
          details: [{ appID: 'TEAM123.com.echango.promo', paths: ['/promo/*'] }],
        },
      });
    });
  });

  describe('redirectToStore', () => {
    it("affiche une page d'attente tant qu'aucun lien store n'est configuré", () => {
      const controller = new AppLinksController(configWith({}));
      const res = fakeResponse();
      controller.redirectToStore(undefined, res as never);
      expect(res.redirectedTo).toBeUndefined();
      expect(res.htmlSent).toContain('echango Promo');
    });

    it('redirige vers PLAY_STORE_URL pour un user-agent Android', () => {
      const controller = new AppLinksController(
        configWith({ PLAY_STORE_URL: 'https://play.google.com/store/apps/details?id=x' }),
      );
      const res = fakeResponse();
      controller.redirectToStore('Mozilla/5.0 (Linux; Android 14)', res as never);
      expect(res.redirectedTo).toBe('302 https://play.google.com/store/apps/details?id=x');
    });

    it('redirige vers APP_STORE_URL pour un user-agent iPhone', () => {
      const controller = new AppLinksController(
        configWith({ APP_STORE_URL: 'https://apps.apple.com/app/id123' }),
      );
      const res = fakeResponse();
      controller.redirectToStore('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)', res as never);
      expect(res.redirectedTo).toBe('302 https://apps.apple.com/app/id123');
    });
  });
});

import { Controller, Get, Headers, Res } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Response } from 'express';

const COMING_SOON_HTML = `<!doctype html>
<html lang="fr">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>echango Promo</title>
  </head>
  <body style="font-family: sans-serif; text-align: center; padding: 3rem 1.5rem;">
    <h1>echango Promo arrive bientôt</h1>
    <p>L'application n'est pas encore disponible en téléchargement.</p>
  </body>
</html>`;

/**
 * Dédié au sous-domaine promo.echango.com (App Links Android / Universal
 * Links iOS, partage d'une promo — croissance organique). Restreint via
 * `host` pour ne jamais entrer en conflit avec `GET /promo/:id` de
 * `PromoController` (API JSON de l'app mobile, sur un tout autre domaine) —
 * le DNS/reverse proxy doit router ce host vers ce même backend sans
 * réécrire l'en-tête Host (voir docs/DEPLOIEMENT_STORES.md).
 *
 * Sert :
 * - les 2 fichiers de vérification qui prouvent à Android/iOS que ce
 *   domaine peut ouvrir l'app directement (sinon le lien s'ouvre dans le
 *   navigateur, sans casser quoi que ce soit) ;
 * - une redirection vers la fiche store pour qui n'a pas l'app installée
 *   (ou une page d'attente tant que l'app n'est pas publiée) — jamais la
 *   promo elle-même : décision produit actée, on pousse à l'installation,
 *   pas à consulter un site.
 *
 * Toutes les valeurs réelles (package name, empreinte de certificat, team
 * ID, bundle ID, liens store) sont vides tant que l'app n'est pas publiée
 * — les renseigner dans `.env` suffit, aucun redéploiement de code requis.
 */
@Controller({ host: 'promo.echango.com' })
export class AppLinksController {
  constructor(private readonly config: ConfigService) {}

  @Get('.well-known/assetlinks.json')
  assetlinks(): unknown[] {
    const packageName = this.config.get<string>('ANDROID_PACKAGE_NAME', '');
    const fingerprint = this.config.get<string>(
      'ANDROID_SHA256_CERT_FINGERPRINT',
      '',
    );
    // Tableau vide : fichier syntaxiquement valide mais qui ne vérifie
    // aucune app — Android retombe sur l'ouverture navigateur, pas d'erreur.
    if (!packageName || !fingerprint) return [];

    return [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: packageName,
          sha256_cert_fingerprints: [fingerprint],
        },
      },
    ];
  }

  @Get('.well-known/apple-app-site-association')
  appleAppSiteAssociation(): Record<string, unknown> {
    const teamId = this.config.get<string>('IOS_TEAM_ID', '');
    const bundleId = this.config.get<string>('IOS_BUNDLE_ID', '');
    if (!teamId || !bundleId) {
      return { applinks: { apps: [], details: [] } };
    }

    return {
      applinks: {
        apps: [],
        details: [{ appID: `${teamId}.${bundleId}`, paths: ['/promo/*'] }],
      },
    };
  }

  /**
   * `:id` fait partie du chemin (il doit correspondre à ce qui a été
   * partagé) mais n'est jamais lu : on ne montre jamais la promo ici,
   * uniquement une redirection vers le store — ou la page d'attente si
   * le lien du store n'est pas encore configuré.
   */
  @Get('promo/:id')
  redirectToStore(
    @Headers('user-agent') userAgent: string | undefined,
    @Res() res: Response,
  ): void {
    const isIOS = /iPhone|iPad|iPod/i.test(userAgent ?? '');
    const storeUrl = this.config.get<string>(
      isIOS ? 'APP_STORE_URL' : 'PLAY_STORE_URL',
      '',
    );

    if (storeUrl) {
      res.redirect(302, storeUrl);
      return;
    }
    res.status(200).type('html').send(COMING_SOON_HTML);
  }
}

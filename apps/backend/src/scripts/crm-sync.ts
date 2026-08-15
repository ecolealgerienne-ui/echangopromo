/**
 * Déclenche l'export vers le CRM Odoo **depuis le serveur**, sans jeton HTTP.
 *
 * ── Pourquoi cette commande existe ────────────────────────────────────────
 *
 * Le déclencheur HTTP (`POST /crm/sync`) exige un JWT d'administrateur de
 * Promo. Or l'exploitant qui déploie est déjà **dans le conteneur** : lui
 * demander de se connecter à son propre produit pour lancer un travail
 * d'exploitation, c'est ajouter un mot de passe à retrouver au pire moment —
 * et pousser à confondre ce JWT avec `CRM_SYNC_TOKEN`, qui n'a rien à voir
 * (l'un authentifie un humain auprès de Promo, l'autre authentifie Promo
 * auprès d'Odoo).
 *
 * ⚠️ **Être dans le conteneur EST l'authentification.** Quiconque peut lancer
 * cette commande peut déjà lire la base et le `.env` : exiger un jeton de plus
 * ne protégerait rien, il ne ferait qu'ajouter une étape à franchir.
 *
 * ── ⚠️ Le même code que la tâche de 04:00, pas un chemin parallèle ────────
 *
 * On démarre le **contexte Nest complet** et on demande `CrmPushService` —
 * exactement l'objet que la tâche planifiée utilise. Réécrire ici une version
 * simplifiée de l'envoi produirait un déclencheur qui « marche » sans rien
 * prouver de celui qui tourne la nuit (règle #30).
 *
 * Usage, dans le conteneur :
 *     node dist/scripts/crm-sync.js
 *     npm run crm:sync:prod
 *
 * En développement :
 *     npm run crm:sync
 */
import 'dotenv/config';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../app.module';
import { CrmPushService } from '../crm/crm-push.service';

async function main(): Promise<number> {
  const journal = new Logger('crm:sync');
  // ⚠️ **Silencieux à l'amorçage, bavard ensuite.** Nest journalise une ligne
  // par module chargé : quarante lignes avant la seule qui compte. On démarre
  // donc en `warn` — un échec d'amorçage reste visible — puis on rouvre le
  // niveau `log`, parce que ce sont les journaux du service lui-même qui
  // portent le nombre de pages, les divergences d'équivalence et le refus de
  // tourner sans jeton.
  const app = await NestFactory.createApplicationContext(AppModule, {
    logger: ['warn', 'error'],
  });
  app.useLogger(['log', 'warn', 'error']);

  try {
    const resultat = await app.get(CrmPushService).pousser();

    if (!resultat) {
      // ⚠️ **Ce n'est pas une panne, et il faut le dire autrement qu'un
      // échec** : sans `CRM_SYNC_URL`/`CRM_SYNC_TOKEN`, le module Odoo peut
      // simplement ne pas encore exister. Le service a déjà journalisé le
      // détail ; on sort en 2 pour qu'un script appelant puisse distinguer
      // « rien envoyé » de « envoi raté » (1).
      journal.warn(
        'Rien envoyé : CRM_SYNC_URL / CRM_SYNC_TOKEN absents du .env — ' +
          'voir docs/DEPLOIEMENT_CRM_VPS.md',
      );
      return 2;
    }

    journal.log(
      `Lot ${resultat.lot} — ${resultat.envoyees} fiche(s) en ` +
        `${resultat.pages} page(s), acquitté.`,
    );
    journal.log(
      'Vérifier côté Odoo : CRM → echango Promo → Journal des lots — deux ' +
        'lignes, « accepté » vrai, « refusées » à zéro.',
    );
    return 0;
  } catch (erreur) {
    // ⚠️ Le message complet, pas seulement « échec » : c'est lui qui dit si
    // Odoo a refusé le jeton, si l'adresse est injoignable, ou si la charge a
    // été rejetée — trois causes qui n'appellent pas le même geste.
    journal.error(
      `Envoi échoué : ${erreur instanceof Error ? erreur.message : String(erreur)}`,
    );
    return 1;
  } finally {
    await app.close();
  }
}

main()
  .then((code) => process.exit(code))
  .catch((erreur) => {
    console.error(erreur);
    process.exit(1);
  });

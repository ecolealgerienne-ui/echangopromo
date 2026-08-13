import { IsEnum } from 'class-validator';
import { PromoModerationStatus } from '../../promo/entities/promo.entity';

/**
 * Corps commun aux trois résolutions de modération (masquer / vérifier OK /
 * avertir) — ajouté le 2026-08-13 pour fermer une course entre modérateurs.
 *
 * ── Ce que ce champ empêche, et pourquoi il n'a rien d'académique ───────────
 *
 * Les trois résolutions étaient des `UPDATE ... WHERE id = ?` inconditionnels.
 * **Deux modérateurs sur la même promo produisaient une perte de décision
 * silencieuse** : A masque, B — dont l'écran datait d'avant — vérifie OK. La
 * promo redevient publique **et** ouvre une fenêtre d'ignore de 30 jours qui la
 * rend insensible aux signalements suivants. Les deux reçoivent `200`, les deux
 * gestes entrent au journal comme deux succès indépendants, et personne
 * n'apprend jamais que la décision de A a été annulée.
 *
 * Ce n'était pas théorique depuis le 2026-08-13 : la file de modération est
 * devenue **nationale et non partitionnée** avec la suppression du découpage
 * administratif. Tous les agents du pays voient la même file, et rien ne leur
 * attribue un lot. C'est le seul point du chantier « agent global » qui pouvait
 * corrompre des données sans qu'aucun écran ni aucun journal ne le montre.
 *
 * ── Pourquoi le client, et pourquoi obligatoire ─────────────────────────────
 *
 * L'état attendu vient du client parce que **le client est le seul à savoir ce
 * que le modérateur a vu**. Les deux écrans qui appellent ces routes affichent
 * déjà `moderationStatus` : la file (`SIGNALEE` par construction) et le détail
 * d'une promo (`admin_promo_detail_screen`, qui l'affiche explicitement). La
 * valeur existe des deux côtés ; il ne restait qu'à la faire voyager.
 *
 * ⚠️ **Obligatoire, pas optionnel** — règle 29. Un champ facultatif ferait
 * retomber tout appelant qui l'oublie sur l'ancien comportement, sans le dire :
 * la protection existerait dans le code et serait absente à l'exécution, ce qui
 * est pire que son absence puisqu'on la croirait acquise.
 *
 * ⚠️ Et un `@Body()` typé en ligne n'aurait **rien validé du tout** (règle 34) :
 * le `ValidationPipe` ne valide que les classes décorées. D'où cette DTO —
 * jusqu'ici les trois routes ne prenaient aucun corps, et le `{"reason": …}`
 * que trois bancs leur envoyaient était **silencieusement jeté** par
 * `whitelist: true`.
 *
 * ── Ce que ce champ n'interdit PAS ──────────────────────────────────────────
 *
 * Revenir sur sa propre décision reste possible : un admin qui ouvre une promo
 * déjà masquée voit `masquee` à l'écran, l'envoie, et son avertissement passe.
 * C'est le flux corrigé le 2026-08-05 (« avertir depuis MASQUÉE »), et il est
 * conservé intact — la garde ne refuse que si l'état a changé **depuis
 * l'affichage**, jamais parce qu'il n'est pas `SIGNALEE`.
 */
export class ResolveModerationDto {
  @IsEnum(PromoModerationStatus)
  expectedModerationStatus: PromoModerationStatus;
}

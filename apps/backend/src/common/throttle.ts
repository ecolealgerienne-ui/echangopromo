/**
 * Multiplicateur de TOUS les plafonds ci-dessous. Vaut 1 par défaut : la
 * production est donc **inchangée tant que la clé est absente**.
 *
 * ── Pourquoi il existe ─────────────────────────────────────────────────────
 *
 * Le lot de bancs passait 15 minutes à DORMIR pour 13 minutes d'exécution.
 * Ce n'est pas une question de latence — les réponses sont sous la seconde en
 * local — mais de fenêtre : `ttl` vaut 60 s, donc un seau de 5/min ne se
 * recharge qu'au bout d'une minute, quelle que soit la vitesse du serveur.
 * Attendre moins ne fait pas gagner du temps, ça fabrique des 429 déguisés en
 * échecs métier — le faux négatif le plus coûteux de ce dépôt.
 *
 * Le seul levier honnête est donc d'élargir les seaux LÀ OÙ ON MESURE, sans
 * toucher à ce que la production applique.
 *
 * ── ⚠️ Ce qu'il ne faut jamais faire ───────────────────────────────────────
 *
 * Ne jamais le poser en production : ces plafonds sont l'unique défense de la
 * règle 2 (aucun compteur de tentatives par compte n'existe). Un facteur de 20
 * multiplie par vingt la vitesse d'un brute-force en ligne.
 *
 * ⚠️ **Et aucun banc n'éprouve le limiteur lui-même.** Tous les bancs traitent
 * un 429 comme « pas un verdict » et le contournent ; aucun n'affirme qu'il
 * refuse. Relever les seaux en local ne casse donc rien aujourd'hui — mais
 * c'est parce qu'un trou de couverture existe, pas parce que c'est sûr.
 */
function facteurDeSeau(): number {
  const brut = process.env.THROTTLE_FACTOR;
  if (brut === undefined || brut.trim() === '') return 1;
  const n = Number(brut);
  // ⚠️ `Number` est bien trop accueillant pour servir de garde : `Number('')`
  // vaut 0 et `Number(true)` vaut 1 (règle 34). D'où le contrôle explicite,
  // et le repli JOURNALISÉ — une valeur illisible ne doit pas être
  // indiscernable d'une absence.
  if (!Number.isFinite(n) || n < 1) {
    console.warn(
      `[throttle] THROTTLE_FACTOR illisible ou < 1 (${brut}) — repli sur 1`,
    );
    return 1;
  }
  if (n !== 1) {
    console.warn(
      `[throttle] ⚠️  THROTTLE_FACTOR=${n} — tous les plafonds sont multipliés ` +
        `par ${n}. Réservé aux environnements de mesure : JAMAIS en production.`,
    );
  }
  return n;
}

export const THROTTLE_FACTOR = facteurDeSeau();
/**
 * Connexions — 50 tentatives/minute par IP (décision produit du 2026-08-13,
 * relevé depuis 5).
 *
 * ── Pourquoi ce seau a été séparé du seau strict ────────────────────────────
 *
 * Les trois `login` partageaient jusqu'ici `STRICT_THROTTLE` avec `register` et
 * `report`. **C'est une IP qui est comptée, pas un compte** — et en Algérie le
 * parc mobile sort massivement derrière du NAT opérateur : cinq tentatives par
 * minute, ce n'est pas cinq essais pour un utilisateur, c'est **cinq
 * utilisateurs par minute pour tout un bloc d'abonnés**. Le sixième se voyait
 * refuser des identifiants parfaitement valides, sur une app dont l'usage
 * dominant est la consultation.
 *
 * Le coût était déjà mesuré ailleurs dans le dépôt : une connexion d'agent
 * consomme **deux** requêtes de ce seau (l'écran tente `POST /admin/login` puis
 * `POST /agent/login`), et la moitié des bancs portent un avertissement « à
 * lancer isolé, le seau est vide pendant une minute ».
 *
 * ── ⚠️ Ce que ce relèvement coûte, et il faut le lire ───────────────────────
 *
 * **Aucun compteur de tentatives par compte n'existe** (`CommercantService
 * .login` compare et refuse, sans rien mémoriser). Ce plafond IP est donc
 * l'unique défense de la règle 2, et le relever multiplie par dix la vitesse
 * d'un brute-force en ligne.
 *
 * Sur les secrets d'aujourd'hui, c'est tenable : un mot de passe d'agent/admin
 * est hors de portée, et `PIN_SET_PATTERN` impose **6 chiffres au minimum**
 * depuis la création du produit — un million de combinaisons, soit 14 jours à
 * 50/min depuis une IP, là où un attaquant sérieux disposerait de toute façon
 * de plusieurs IP.
 *
 * **Le point dur est ailleurs, et il est réel** : `PIN_VERIFY_PATTERN` accepte
 * `\d{4,12}` — quatre chiffres — pour ne pas enfermer dehors les comptes créés
 * avant le passage à six. Dix mille combinaisons : **3 h 20 à 50/min**, contre
 * 33 h à 5/min. Pour ces comptes-là, et pour eux seuls, le relèvement fait
 * passer une attaque de « une journée et demie » à « une nuit ».
 *
 * La contre-mesure qui referme ça n'est pas un plafond — c'est de retirer les
 * PIN à 4 chiffres du parc (forcer la remise à 6 à la prochaine connexion) ou
 * un compteur de tentatives **par compte**, qui ne dépend pas de l'IP. Tant que
 * ni l'un ni l'autre n'existe, ce commentaire est le seul endroit où le risque
 * est écrit ; il ne tient rien (règle 30), il informe la prochaine décision.
 */
export const AUTH_THROTTLE = {
  default: { limit: 50 * THROTTLE_FACTOR, ttl: 60_000 },
};

/**
 * Limite stricte pour les endpoints non authentifiés ou basés sur un
 * identifiant déclaratif non vérifié — 5 requêtes/minute par IP, plus
 * restrictif que la limite globale par défaut (60/min, voir
 * `ThrottlerModule.forRoot` dans `app.module.ts`).
 *
 * ⚠️ **Ne couvre plus les connexions depuis le 2026-08-13** (voir
 * `AUTH_THROTTLE`). Il ne reste que deux routes, et ce sont les deux dont le
 * plafond EST la protection, pas une gêne :
 * - `POST /commercant/register` — création de compte ; 50/min/IP, c'est une
 *   ferme à comptes ;
 * - `POST /report` — **le cas fondateur de la règle 7**. Trois signalements
 *   d'appareils distincts masquent la promo d'un concurrent, et l'`X-Device-Id`
 *   n'est jamais vérifié : à 5/min une IP en masque une par minute et demie, à
 *   50/min elle en masquerait seize. Le relèvement des connexions ne devait pas
 *   emporter celle-ci avec lui — c'est pourquoi les deux seaux sont séparés
 *   plutôt qu'un seul chiffre changé.
 */
export const STRICT_THROTTLE = {
  default: { limit: 5 * THROTTLE_FACTOR, ttl: 60_000 },
};

/**
 * Limite pour les actions sensibles déjà authentifiées (création de
 * ressource par un agent, upload, actions destructrices admin, gestion de
 * promo) — moins stricte que `STRICT_THROTTLE` car un usage légitime peut
 * en émettre plusieurs à la suite (ex. un agent onboardant plusieurs
 * commerces), mais toujours en dessous de la limite globale pour qu'un
 * compte compromis ne puisse pas spammer ces routes (audit V1 §2).
 */
export const SENSITIVE_ACTION_THROTTLE = {
  default: { limit: 20 * THROTTLE_FACTOR, ttl: 60_000 },
};

/**
 * Lecture publique intrinsèquement bavarde : explorer une carte produit
 * légitimement plusieurs requêtes par minute, là où le reste de l'API en
 * produit une par action. La limite globale (60/min) était atteinte en
 * quelques gestes — retour terrain 2026-07-30, où le client se voyait
 * refuser sa propre carte après quelques dézooms.
 *
 * Reste bornée plutôt qu'illimitée : l'endpoint est non authentifié. Le
 * coût unitaire d'une requête est faible et son résultat plafonné
 * (`MAX_MAP_COMMERCANTS`, clé de `.env` depuis le 2026-08-12 — le plafond
 * reste, seule sa provenance change), ce qui justifie d'être plus permissif
 * ici sans ouvrir la porte à un abus.
 *
 * La vraie économie est côté client : la carte n'émet plus qu'une requête
 * par geste (temporisation) et ne redemande que le terrain qu'elle n'a pas
 * déjà (zone chargée élargie) — sans quoi aucune limite ne suffirait.
 */
export const MAP_THROTTLE = {
  default: { limit: 180 * THROTTLE_FACTOR, ttl: 60_000 },
};

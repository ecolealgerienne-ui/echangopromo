# Benchmark concurrentiel — echango Promo face au monde

Comparatif fonctionnel établi le 2026-07-11 par recherche web, en complément de
`docs/AUDIT_V0.md`/`AUDIT_V1.md` (audits internes). Une version visuelle
(tableau interactif, thème clair/sombre) existe en parallèle dans
`docs/echango-benchmark.html` — à ouvrir directement dans un navigateur ; ce
document-ci en est la version texte, plus facile à differ.

Sept applications déjà lancées, en Europe, en Asie, en Amérique du Nord et en
Afrique, qui résolvent une variante du même problème que le pilote de
Djelfa : connecter des commerces de proximité à des clients à pied. Comparatif
colonne par colonne, pas un classement — chacune a fait des arbitrages
différents pour un contexte différent.

## Verdict

**echango Promo est la seule des huit à avoir été pensée pour le commerce
informel** : pas d'OTP, onboarding par un agent qui se déplace en personne,
PIN à la place d'un mot de passe, aucune obligation de paiement en ligne.
Toutes les autres supposent un commerçant déjà « digitalisé » — compte
bancaire, smartphone maîtrisé, parfois un point de vente électronique.

En contrepartie, **echango Promo est la seule à n'avoir aucun modèle
économique** : les six autres financent leur plateforme par une commission, un
abonnement marchand ou de la publicité display. Le pilote reste donc un choix
produit à trancher avant toute extension au-delà d'un quartier pilote.

## Comparatif fonctionnel

Légende : ✓ présent · ± présent sous une forme différente ou partielle · —
absent.

| Dimension | **echango Promo** | Too Good To Go | OLIO | Karrot (Danggeun) | Nearbuy | Groupon | Bonial / Kimbino |
|---|---|---|---|---|---|---|---|
| Modèle économique | — gratuit, sans commission | ± commission/abonnement commerçant | — don, financé par mécénat | ± gratuit + services pro payants | ± commission sur bon prépayé | ± commission sur bon prépayé | ± publicité des enseignes |
| Portée géographique | un quartier | ville → international | quartier → international | quartier (rayon 6 km) | ville (33 villes) | ville → international | national (grandes enseignes) |
| Tout commerce, ou une niche ? | tout commerce (6 catégories) | — alimentaire uniquement | ± alimentaire + objets | tout commerce + occasion | ± loisirs/restauration/beauté | tout commerce + voyages | ± grande distribution |
| Réduction réelle affichée (prix avant/après) | ✓ obligatoire à la création | ± prix réduit, pas systématique | — gratuit, pas de prix | — prix libre, non structuré | ± % affiché | ± % affiché | — prospectus, pas item par item |
| Compte client requis pour parcourir | — navigation anonyme | ✓ | ✓ | ✓ + vérif. téléphone/GPS | ✓ | ✓ | — |
| Paiement ou réservation dans l'app | — retrait en magasin, non réservable | ✓ achat du sac à l'avance | — demande, pas de paiement | ± souvent en personne | ✓ bon prépayé obligatoire | ✓ bon prépayé obligatoire | — |
| Modération par signalement client | ✓ seuil de 3 signalements distincts | ± notation/avis, pas de report | ✓ | ± note de confiance par profil | — | — | — contenu fourni par l'enseigne |
| Onboarding terrain du commerce informel | ✓ agent qui visite en personne | — équipe commerciale classique | ± collecte bénévole, pas d'onboarding | — auto-inscription | — équipe commerciale classique | — self-service + équipe commerciale | — partenariats grandes enseignes |
| Vérification d'identité commerçant | ± registre requis si auto-inscrit | — commerce déjà établi | — partenaires enseignes connues | ± géolocalisation + téléphone | — | — | — |
| Partage social natif | ✓ WhatsApp | ± | ± | ± | ✓ | ✓ | ± |
| Multi-langue avec RTL natif | ✓ FR / EN / AR | ± mondial, RTL non prioritaire | ± | — coréen d'abord | — anglais/hindi | ± | ± plusieurs pays UE |
| Notifications push | — in-app uniquement (phase 2) | ✓ alertes sur favoris | ✓ alertes personnalisées | ✓ | ✓ | ✓ | ✓ alertes catalogue |

## Les sept applications

- **Too Good To Go** — « sacs surprise » de nourriture invendue en fin de
  journée, à prix cassé, réservés et payés dans l'app avant le retrait.
  Europe → mondial. [toogoodtogo.com](https://www.toogoodtogo.com/en-us/how-does-the-app-work)
- **OLIO** — partage gratuit de surplus alimentaire et d'objets entre voisins,
  avec des grandes enseignes comme donateurs partenaires. UK → mondial.
  [olioapp.com](https://olioapp.com/en/)
- **Karrot (Danggeun Market)** — petites annonces d'occasion restreintes à un
  rayon de 6 km, étendues depuis 2023 aux profils commerçants (salons de
  coiffure, services). Corée du Sud.
  [franvia.com](https://www.franvia.com/2026/03/karrot-market-korea-neighborhood-marketplace-culture.html)
- **Nearbuy** — bons de réduction prépayés sur restaurants, spas et loisirs
  dans 33 villes indiennes, à présenter au commerçant. Inde.
  [nearbuy.com](https://www.nearbuy.com/help/aboutus)
- **Groupon** — le pionnier du bon de réduction local, devenu une place de
  marché mondiale (local, séjours, produits). États-Unis → mondial.
  [groupon.com](https://www.groupon.com/local)
- **Bonial / Kimbino** — catalogues et prospectus des grandes enseignes
  (supermarchés, bricolage, ameublement) géolocalisés, sans transaction dans
  l'app. France, Allemagne… [bonial.com](https://www.bonial.com/en/)
- **Jumia Deals** — petites annonces gratuites entre particuliers dans une
  vingtaine de pays africains — proche par le contexte informel, mais pas un
  système de promos commerçants.
  [Jumia (Wikipédia)](https://en.wikipedia.org/wiki/Jumia)

## Ce que ça donne pour echango Promo

### À emprunter

- **Le badge de confiance progressif, à la Karrot** — la vérification par
  géolocalisation + téléphone de Karrot fait le même travail que le registre
  de commerce d'echango, sans document — à envisager en complément pour les
  commerçants qui n'ont vraiment aucun justificatif.
- **L'alerte « favori disponible » de TGTG/OLIO** — déjà noté dans l'audit
  fonctionnel : une fois le bug des favoris corrigé, un simple badge
  « nouvelle promo chez un favori » au lancement de l'app (sans infra push)
  capte une bonne partie de ce bénéfice de rétention à coût nul.
- **Le profil commerçant de Karrot (2023)** — système de réservation intégré
  pour les salons/services, une piste d'extension au-delà de la simple promo
  ponctuelle, une fois le pilote validé.

### Ce qui reste unique à echango

- **Zéro barrière à l'entrée commerçant** — aucune des sept ne permet à un
  commerçant sans compte bancaire ni smartphone maîtrisé de publier une offre
  en quelques minutes avec l'aide d'un agent — c'est le vrai créneau non
  couvert par la concurrence mondiale.
- **Aucune transaction, aucune commission** — toutes les autres captent une
  commission ou un abonnement. echango Promo est une vitrine pure : le client
  se déplace, paie en magasin — plus simple à adopter, mais aussi plus
  difficile à monétiser une fois le pilote terminé.
- **RTL et arabe comme langue de premier rang** — aucun concurrent identifié
  ne traite l'arabe autrement qu'en langue additionnelle tardive — la mobile
  app d'echango a été conçue avec le RTL dès la V0.

---

Comparatif établi à partir des sources citées ci-dessus (recherche web,
juillet 2026) et de l'état du code echango Promo au 2026-07-11 (branche
`claude/echango-promo-testing-45zh04`). Les fonctionnalités concurrentes
évoluent vite — à revalider avant toute décision produit structurante.

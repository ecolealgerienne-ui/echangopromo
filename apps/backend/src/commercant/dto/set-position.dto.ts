import { IsLatitude, IsLongitude } from 'class-validator';

/**
 * Pose ou corrige **uniquement** la position du commerce.
 *
 * ── Pourquoi une route à part, et pas `PATCH /commercant/me` ───────────────
 *
 * Parce que `updateProfile` allume `profilePendingReview` dès qu'un seul champ
 * change — et que ce drapeau **bloque la publication**. Un commerçant à qui l'on
 * refuse de publier faute de position, et qui corrige par la route générale,
 * entre aussitôt dans un **second** blocage, plus long que le premier :
 * « un administrateur doit valider votre profil ». Deux refus successifs pour un
 * seul geste correctif.
 *
 * Ce n'est pas une hypothèse : le décor de test s'est saboté exactement ainsi le
 * 2026-08-05 (« un décor qui répare un profil se sabote donc lui-même »,
 * `docs/status_v0.1.md`).
 *
 * ⚠️ Les deux champs sont **obligatoires** : une latitude seule est une requête
 * cassée, pas une position partielle. Contrairement à `GET /promo`, aucun
 * `@Transform` n'est nécessaire — un corps JSON porte déjà des nombres, alors
 * qu'une query string ne porte que du texte.
 */
export class SetCommercantPositionDto {
  @IsLatitude()
  latitude: number;

  @IsLongitude()
  longitude: number;
}

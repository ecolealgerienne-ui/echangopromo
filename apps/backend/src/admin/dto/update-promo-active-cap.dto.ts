import { IsInt, Max, Min, ValidateIf } from 'class-validator';

/**
 * Plafond de promos actives propre à un commerçant.
 *
 * ── `null` est une valeur, pas une absence ─────────────────────────────────
 *
 * Il remet le commerçant sur le réglage global (`PROMO_ACTIVE_CAP`). D'où
 * `@ValidateIf(… !== null)` plutôt que `@IsOptional()` seul : ce dernier
 * laisserait passer `null` **et** l'omission du champ, deux gestes différents
 * qu'on ne pourrait plus distinguer côté service.
 *
 * ── Les bornes, et pourquoi elles existent ─────────────────────────────────
 *
 * ⚠️ **Un `@IsInt()` sans plafond n'est pas une borne** (règle #34). La colonne
 * est un `integer` Postgres : au-delà de 2 147 483 647, l'insertion lève un
 * `22003` que personne ne rattrape — un 500 là où un refus de validation était
 * dû. Et bien avant cette limite, un plafond de 10 000 promos actives n'a
 * aucun sens métier : il ne réglerait plus rien, il retirerait la garde.
 *
 * `0` est **autorisé et volontaire** : il empêche un commerçant de publier
 * sans le suspendre — une mesure graduée, réversible, qui laisse ses promos
 * existantes en ligne.
 */
export class UpdatePromoActiveCapDto {
  @ValidateIf((_, value) => value !== null)
  @IsInt()
  @Min(0)
  @Max(50)
  plafond!: number | null;
}

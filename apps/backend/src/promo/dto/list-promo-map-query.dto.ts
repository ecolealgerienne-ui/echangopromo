import { Transform } from 'class-transformer';
import { IsEnum, IsLatitude, IsLongitude, IsOptional } from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';

/**
 * Zone visible de la carte (specs carte "autour de moi"). Contrairement aux
 * autres listes, la pagination page/limit n'a pas de sens ici : on ne peut
 * pas afficher "la page 2" d'une carte. Le volume est borné autrement, par
 * `MAX_MAP_COMMERCANTS` — **une clé de `.env`** depuis le 2026-08-12, lue par
 * `PromoService.maxMapCommercants()` et non plus une constante — avec un
 * drapeau `truncated` renvoyé au client plutôt qu'une troncature silencieuse
 * (règle d'audit #15).
 *
 * Le cas d'une zone à cheval sur l'antiméridien (est < ouest) n'est pas
 * traité : hors de portée d'un produit déployé en Algérie, et le gérer
 * imposerait un OR sur la longitude qui casserait l'usage de l'index.
 */
export class ListPromoMapQueryDto {
  @IsLatitude()
  @Transform(({ value }: { value: unknown }) => Number(value))
  north!: number;

  @IsLatitude()
  @Transform(({ value }: { value: unknown }) => Number(value))
  south!: number;

  @IsLongitude()
  @Transform(({ value }: { value: unknown }) => Number(value))
  east!: number;

  @IsLongitude()
  @Transform(({ value }: { value: unknown }) => Number(value))
  west!: number;

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;
}

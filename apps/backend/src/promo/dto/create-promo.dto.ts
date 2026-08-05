import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDate,
  IsEnum,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  Max,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PRIX_MAX } from '../entities/promo.entity';

export class CreatePromoDto {
  @IsString()
  @MinLength(2)
  @MaxLength(140)
  description: string;

  @IsNumber()
  @IsPositive()
  @Max(PRIX_MAX)
  prixAvant: number;

  @IsNumber()
  @IsPositive()
  @Max(PRIX_MAX)
  prixApres: number;

  @IsEnum(Categorie)
  categorie: Categorie;

  /**
   * Clés des objets S3, déjà uploadées (`POST /storage/upload`) — 1 à 3,
   * ordonnées, la première étant la photo principale (décision produit
   * 2026-07-12).
   */
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(3)
  @IsString({ each: true })
  @MinLength(1, { each: true })
  photoKeys: string[];

  /**
   * **La façon dont l'app doit exprimer une durée.** Ignoré si `asDraft`.
   *
   * Le client envoyait une `dateFin` absolue, qu'il calculait sur **son
   * horloge** (`DateTime.now().add(...)`) ; le serveur la comparait ensuite à
   * la sienne, sans tolérance. Un téléphone en avance de quelques minutes se
   * voyait donc refuser une durée pourtant légale, avec
   * `PROMO_DATE_FIN_EXCEEDS_MAX` — dont le message interpole une valeur et
   * n'est donc pas traduit. Envoyer la durée laisse la seule horloge qui
   * valide faire le calcul (revue 2026-08-05, règle #32).
   *
   * Les bornes ne sont pas recopiées ici : `resolveDateFin` applique
   * `PROMO_MAX_DURATION_DAYS`, et lui seul.
   */
  @IsOptional()
  @IsNumber()
  @IsPositive()
  dureeJours?: number;

  /**
   * ⚠️ **Historique — ne plus émettre.** Conservé pour les clients déjà
   * installés qui envoient encore une date absolue ; `dureeJours` l'emporte
   * quand les deux sont présents. À retirer quand le parc aura tourné.
   *
   * Ignoré si `asDraft`. Si les deux sont omis, la date est calculée à
   * `+PROMO_DEFAULT_DURATION_DAYS` jours (5 par défaut), plafonnée à
   * `PROMO_MAX_DURATION_DAYS` (7 par défaut).
   */
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  dateFin?: Date;

  /** Enregistre en brouillon (non publiée, non comptée dans le plafond de 5) au lieu de publier immédiatement. */
  @IsOptional()
  @IsBoolean()
  asDraft?: boolean;
}

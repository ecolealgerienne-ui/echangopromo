import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsISO31661Alpha2,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN } from '../pin.constants';
import {
  ADRESSE_MAX_LENGTH,
  NOM_MAX_LENGTH,
} from '../entities/commercant.entity';
import { EstTelephoneDuPays } from './telephone-du-pays.validator';

export class CreateCommercantByAgentDto {
  @EstTelephoneDuPays()
  telephone: string;

  /**
   * Pays du numéro, ISO 3166-1 alpha-2. Absent ⇒ `DZ` : le pilote est algérien
   * et l'app pré-sélectionne l'Algérie. C'est ce pays qui décide de la forme
   * normalisée et qui entre dans l'unicité `(pays, telephone)` — deux
   * commerçants de pays différents peuvent légitimement porter les mêmes
   * chiffres nationaux.
   */
  @IsOptional()
  @IsISO31661Alpha2()
  pays?: string;

  @IsString()
  @MinLength(2)
  @MaxLength(NOM_MAX_LENGTH)
  nom: string;

  /**
   * Choisi par l'agent en personne (décision produit 2026-07-13, remplace
   * la revendication publique par téléphone seul) — l'agent le communique
   * directement au commerçant lors de la visite, aucune fenêtre publique
   * où un tiers connaissant juste le numéro pourrait s'approprier le
   * compte avant le vrai commerçant.
   */
  @Matches(PIN_SET_PATTERN, { message: PIN_SET_MESSAGE })
  pin: string;

  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(ADRESSE_MAX_LENGTH)
  adresse?: string;

  @IsEnum(Categorie)
  categorie: Categorie;

  /** Clé S3 de la photo du commerce, déjà uploadée (optionnel). */
  @IsOptional()
  @IsString()
  photoKey?: string;

  /**
   * Position GPS du commerce — **obligatoire depuis le 2026-08-12**, alors
   * qu'elle reste facultative à l'auto-inscription.
   *
   * ── Pourquoi ici et pas là ────────────────────────────────────────────────
   *
   * L'agent est **physiquement dans le commerce** quand il crée la fiche :
   * c'est la seule capture juste par construction. Le commerçant qui s'inscrit
   * seul peut très bien le faire depuis chez lui, d'où la différence — et c'est
   * `PromoService` qui lui refusera de **publier** tant qu'il n'aura pas posé
   * son point, pas ce DTO qui l'empêchera d'exister.
   *
   * ⚠️ **Sans cette obligation, le blocage de publication ne ferait qu'écoper.**
   * Mesuré le 2026-08-12 sur la base de développement : 44 commerçants sur 53
   * sans position, dont **40 créés après** le correctif du décor du 2026-08-05.
   * Ils viennent tous de cette route, par laquelle passent les neuf sites de
   * `scripts/lib/` qui n'envoyaient aucune coordonnée. Fermer la source vaut
   * mieux que régulariser le parc indéfiniment.
   */
  @IsLatitude()
  latitude: number;

  @IsLongitude()
  longitude: number;
}

import {
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsPhoneNumber,
  IsString,
  IsUUID,
  Matches,
  MinLength,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN } from '../pin.constants';

export class CreateCommercantByAgentDto {
  @IsPhoneNumber('DZ')
  telephone: string;

  @IsString()
  @MinLength(2)
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
  adresse?: string;

  @IsEnum(Categorie)
  categorie: Categorie;

  @IsUUID()
  communeId: string;

  /** Clé S3 de la photo du commerce, déjà uploadée (optionnel). */
  @IsOptional()
  @IsString()
  photoKey?: string;

  /** Position GPS capturée sur l'appareil de l'agent (optionnel). */
  @IsOptional()
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @IsLongitude()
  longitude?: number;
}

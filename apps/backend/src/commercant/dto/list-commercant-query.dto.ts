import {
  IsBoolean,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import {
  CommercantAccountState,
  RegistreStatus,
} from '../entities/commercant.entity';

/** Vue admin (plan de correction, Phase 2) : recherche nom/téléphone/adresse sur l'ensemble des commerçants. */
export class ListCommercantQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  // ⚠️ Les filtres `communeId` et `wilaya` ont été retirés le 2026-08-13.
  //
  // ⚠️ **Ce commentaire annonçait un travail déjà fait, et c'est un défaut en
  // soi.** Il disait « la recherche ne porte que sur le nom et le téléphone.
  // Ajouter `adresse` fait partie du chantier — voir le plan », alors
  // qu'`adresse` avait été ajoutée dans le même lot
  // (`CommercantService.findAllForAdmin`). Un commentaire qui renvoie à un plan
  // survit au plan : il fait relire un document clos pour découvrir que la
  // chose est faite.
  //
  // L'état réel : la recherche texte porte sur **nom, téléphone et adresse**,
  // et c'est le seul moyen de resserrer un écran devenu national. `adresse`
  // étant facultative et en texte libre, resserrer sur elle ne garantit rien —
  // c'est une aide à la recherche, pas un filtre géographique.

  @IsOptional()
  @IsEnum(CommercantAccountState)
  accountState?: CommercantAccountState;

  /** Filtre "en attente de validation registre" — remplace l'ancienne file dédiée. */
  @IsOptional()
  @IsEnum(RegistreStatus)
  registreStatus?: RegistreStatus;

  /** Filtre "modification de profil en attente de validation" (2026-07-12). */
  @IsOptional()
  @Transform(({ value }) => value === 'true')
  @IsBoolean()
  profilePendingReview?: boolean;
}

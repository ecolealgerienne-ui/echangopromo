import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import { CommercantAccountState, RegistreStatus } from '../entities/commercant.entity';

/** Vue admin (plan de correction, Phase 2) : recherche nom/téléphone sur l'ensemble des commerçants. */
export class ListCommercantQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  @IsOptional()
  @IsEnum(CommercantAccountState)
  accountState?: CommercantAccountState;

  /** Filtre "en attente de validation registre" — remplace l'ancienne file dédiée. */
  @IsOptional()
  @IsEnum(RegistreStatus)
  registreStatus?: RegistreStatus;
}

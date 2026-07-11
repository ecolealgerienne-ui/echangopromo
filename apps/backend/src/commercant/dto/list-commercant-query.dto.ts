import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import { CommercantAccountState } from '../entities/commercant.entity';

/** Vue admin (plan de correction, Phase 2) : recherche nom/téléphone sur l'ensemble des commerçants. */
export class ListCommercantQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  @IsOptional()
  @IsEnum(CommercantAccountState)
  accountState?: CommercantAccountState;
}

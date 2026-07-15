import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';

/** Filtres de la file de modération (2026-07-14), en plus du scope agent (géré à part par `scopedCommuneIds`). */
export class ListModerationQueueQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsUUID()
  communeId?: string;

  /** Prépare l'extension multi-wilaya, sans effet tant que Djelfa est la seule wilaya pilote. */
  @IsOptional()
  @IsString()
  @MaxLength(100)
  wilaya?: string;
}

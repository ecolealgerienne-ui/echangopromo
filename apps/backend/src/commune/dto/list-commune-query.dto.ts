import { IsOptional, IsString } from 'class-validator';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';

export class ListCommuneQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsString()
  wilaya?: string;
}

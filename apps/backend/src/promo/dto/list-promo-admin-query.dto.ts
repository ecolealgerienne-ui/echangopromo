import { IsEnum, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import { PromoLifecycleStatus, PromoModerationStatus } from '../entities/promo.entity';

/**
 * Vue admin/agent (plan de correction, Phase 2) : liste globale de toutes
 * les promos, pas seulement celles ayant atteint le seuil de signalements —
 * sans ça, un contenu problématique repéré directement par un modérateur ne
 * pouvait être masqué qu'en attendant 3 signalements clients.
 */
export class ListPromoAdminQueryDto extends PaginationQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(140)
  search?: string;

  @IsOptional()
  @IsUUID()
  communeId?: string;

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;

  @IsOptional()
  @IsEnum(PromoLifecycleStatus)
  lifecycleStatus?: PromoLifecycleStatus;

  @IsOptional()
  @IsEnum(PromoModerationStatus)
  moderationStatus?: PromoModerationStatus;
}

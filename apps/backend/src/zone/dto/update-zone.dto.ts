import { IsOptional, IsString, MinLength } from 'class-validator';

export class UpdateZoneDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  nom?: string;

  @IsOptional()
  @IsString()
  description?: string;
}

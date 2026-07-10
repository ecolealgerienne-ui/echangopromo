import {
  IsArray,
  IsEmail,
  IsOptional,
  IsString,
  IsUUID,
  MinLength,
} from 'class-validator';

export class CreateAgentDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsString()
  @MinLength(2)
  nom: string;

  @IsOptional()
  @IsArray()
  @IsUUID(undefined, { each: true })
  communeIds?: string[];
}

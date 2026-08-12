import { IsEmail, IsString, MinLength } from 'class-validator';

export class CreateAgentDto {
  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  password: string;

  @IsString()
  @MinLength(2)
  nom: string;

  // `communeIds` retiré le 2026-08-13 : un agent n'a plus de territoire.
}

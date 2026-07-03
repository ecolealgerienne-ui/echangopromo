import { IsString, MinLength } from 'class-validator';

export class RequestRegistreVerificationDto {
  /** Clé de l'objet S3 du registre de commerce, déjà uploadé via URL pré-signée. */
  @IsString()
  @MinLength(1)
  registreKey: string;
}

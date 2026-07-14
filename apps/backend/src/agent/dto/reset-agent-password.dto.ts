import { IsString, MinLength } from 'class-validator';

/**
 * Mot de passe agent oublié/perdu — seul l'admin peut le réinitialiser
 * (l'agent ne peut pas le changer lui-même, décision produit 2026-07-14),
 * à communiquer de vive voix. Même contrainte de longueur qu'à la création
 * (`CreateAgentDto`).
 */
export class ResetAgentPasswordDto {
  @IsString()
  @MinLength(8)
  newPassword: string;
}

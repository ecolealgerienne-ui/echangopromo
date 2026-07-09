import { IsArray, IsUUID } from 'class-validator';

export class AssignCommunesDto {
  /** Remplace l'ensemble des communes assignées à l'agent (liste vide = désassignation totale). */
  @IsArray()
  @IsUUID(undefined, { each: true })
  communeIds: string[];
}

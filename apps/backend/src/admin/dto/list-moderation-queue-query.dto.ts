import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';

/**
 * Filtres de la file de modération.
 *
 * ⚠️ **Il n'en reste aucun depuis le 2026-08-13** : `communeId` et `wilaya`
 * sont partis avec le chantier « agent global ». Cette classe est donc un
 * `PaginationQueryDto` nu — et elle est **conservée telle quelle**, pas
 * remplacée par lui dans le contrôleur.
 *
 * La raison est la règle #34 : un `@Query()` doit traverser un DTO décoré qui
 * lui appartient. Nommer le type de cette file lui donne l'endroit où poser le
 * prochain filtre — et il en faudra un, la file étant désormais **nationale**
 * et partagée par tous les agents, sans partition du travail.
 */
export class ListModerationQueueQueryDto extends PaginationQueryDto {}

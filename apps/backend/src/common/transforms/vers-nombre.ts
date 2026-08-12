/**
 * Conversion d'un paramètre de requête numérique.
 *
 * ⚠️ **`@Type(() => Number)` seul ne suffit pas pour une coordonnée**, alors
 * qu'il suffit pour `page`/`limit` — et la différence est ce qui rend le piège
 * invisible. `?page=` (vide) donne `Number('') === 0`, que `@Min(1)` refuse.
 * `?latitude=` donne le même `0`, que **`@IsLatitude()` accepte** : c'est
 * l'équateur, une valeur parfaitement légitime. Le client se retrouverait au
 * large du Gabon sans qu'aucune validation ne bronche.
 *
 * D'où ce transform explicite : une chaîne vide ou blanche devient `NaN`, donc
 * un refus, et **jamais un zéro**. L'absence, elle, reste l'absence — c'est
 * `@IsOptional`/`@ValidateIf` qui décide ensuite si elle est acceptable.
 *
 * ⚠️ Le piège *inverse* n'existe pas, contrairement à ce qu'on pourrait
 * craindre : `class-transformer` construit ses clés depuis l'objet source, donc
 * le callback n'est **jamais appelé** pour un paramètre absent — pas de
 * `Number(undefined)`, pas de `NaN` fabriqué par mégarde.
 *
 * Partagé entre `ListPromoQueryDto` et `ListHighlightQueryDto` : les deux
 * cadrent la même liste, et si la règle change pour l'une elle doit changer
 * pour l'autre (règle #30).
 */
export const versNombre = ({ value }: { value: unknown }): unknown => {
  if (value === undefined || value === null) return value;
  if (typeof value === 'string' && value.trim() === '') return Number.NaN;
  return Number(value);
};

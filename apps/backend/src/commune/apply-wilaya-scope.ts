import { ObjectLiteral, SelectQueryBuilder } from 'typeorm';
import { Commune } from './entities/commune.entity';

/**
 * Restreint une requête aux commerçants d'une wilaya, en traversant
 * `commercant → commune`.
 *
 * ── Pourquoi une fonction plutôt que trois copies ─────────────────────────
 *
 * Elle l'était : `CommercantService.findAllForAdmin`, `PromoService`
 * `.findAllForAdmin` et `ReportService.pendingModerationQueryBuilder` posaient
 * chacun le même filtre. Le critère de la règle #30 n'est pas « ces bouts se
 * ressemblent-ils » mais **« si l'un change, l'autre doit-il changer ? »** — et
 * ici oui : c'est la même question posée trois fois. Aucun commentaire ne les
 * reliait, ce qui ne les rendait pas indépendants pour autant.
 *
 * ⚠️ **La jointure est faite PAR ENTITÉ, pas par relation, et ce n'est pas un
 * détail de style.** Les deux premiers appelants pouvaient écrire
 * `.innerJoin('commercant.commune', 'commune')` parce que `commercant` y est la
 * racine ou une relation. Dans `ReportService`, `commercant` est lui-même une
 * jointure d'entité — la forme par relation y est au mieux fragile. La forme
 * par entité fonctionne dans les trois cas ; c'est donc elle qui est retenue,
 * par uniformité.
 *
 * ⚠️ L'alias `commune` doit rester libre chez l'appelant. Aucun des trois ne
 * l'utilisait (le filtre par commune passe par `commercant.communeId`, sans
 * jointure), mais un quatrième appelant qui joindrait déjà `commune` devrait
 * s'en assurer.
 */
export function applyWilayaScope<T extends ObjectLiteral>(
  qb: SelectQueryBuilder<T>,
  commercantAlias: string,
  wilaya: string,
): SelectQueryBuilder<T> {
  return qb
    .innerJoin(Commune, 'commune', `commune.id = ${commercantAlias}.communeId`)
    .andWhere('commune.wilaya = :wilaya', { wilaya });
}

import {
  registerDecorator,
  ValidationArguments,
  ValidationOptions,
} from 'class-validator';
import { normaliserTelephone, paysOuDefaut } from '../telephone';

/**
 * Remplace `@IsPhoneNumber('DZ')`, qui ne sait pas lire le pays choisi par le
 * commerçant.
 *
 * ⚠️ **`@IsPhoneNumber` ne peut pas prendre sa région d'un autre champ du même
 * DTO** : sa région est un argument figé à la compilation. Elle était donc
 * codée en dur dans les trois DTO — et le jour où la colonne `pays` est
 * arrivée, elle aurait continué de refuser **tout** numéro non algérien, sur
 * un produit qui venait d'annoncer le contraire. Un champ qui existe et que
 * rien n'honore est pire que son absence (règle #31).
 *
 * Le pays est lu sur la propriété voisine (`pays` par défaut) ; absente, c'est
 * `PAYS_PAR_DEFAUT` qui s'applique — la même résolution que le service, parce
 * qu'un validateur qui accepterait ce que le service refuse ne validerait rien.
 */
export function EstTelephoneDuPays(
  proprietePays = 'pays',
  options?: ValidationOptions,
) {
  return function (objet: object, propriete: string): void {
    registerDecorator({
      name: 'estTelephoneDuPays',
      target: objet.constructor,
      propertyName: propriete,
      constraints: [proprietePays],
      options,
      validator: {
        validate(valeur: unknown, args: ValidationArguments): boolean {
          const [champPays] = args.constraints as [string];
          const pays = paysOuDefaut(
            (args.object as Record<string, string | undefined>)[champPays],
          );
          return (
            typeof valeur === 'string' &&
            normaliserTelephone(valeur, pays) !== null
          );
        },
        defaultMessage(args: ValidationArguments): string {
          const [champPays] = args.constraints as [string];
          const pays = paysOuDefaut(
            (args.object as Record<string, string | undefined>)[champPays],
          );
          return `${args.property} doit être un numéro de téléphone valide pour le pays ${pays}`;
        },
      },
    });
  };
}

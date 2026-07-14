import { Matches } from 'class-validator';
import { PIN_SET_MESSAGE, PIN_SET_PATTERN } from '../pin.constants';

/**
 * PIN vraiment oublié (le commerçant ne peut fournir aucun ancien PIN) —
 * l'admin/agent fixe directement un nouveau PIN et le communique par
 * téléphone après avoir identifié l'appelant pendant la conversation,
 * même logique que l'agent qui fixe le PIN en personne à la création
 * (décision produit 2026-07-13, remplace l'ancienne remise à zéro suivie
 * d'une revendication publique).
 */
export class ResetCommercantPinDto {
  @Matches(PIN_SET_PATTERN, { message: PIN_SET_MESSAGE })
  newPin: string;
}

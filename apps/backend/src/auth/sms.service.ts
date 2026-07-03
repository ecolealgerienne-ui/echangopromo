import { Injectable, Logger } from '@nestjs/common';

/**
 * Envoi de SMS OTP — stub en attendant le choix d'un fournisseur (point
 * ouvert §7.5 des specs : coût à chiffrer avant l'extension multi-wilaya).
 * Se contente de logguer le code ; à remplacer par un vrai intégration
 * (ex. Twilio, fournisseur local algérien) sans changer l'interface.
 */
@Injectable()
export class SmsService {
  private readonly logger = new Logger(SmsService.name);

  async send(telephone: string, message: string): Promise<void> {
    this.logger.log(`[SMS stub] -> ${telephone}: ${message}`);
    return Promise.resolve();
  }
}

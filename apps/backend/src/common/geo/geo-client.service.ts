import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { configNumber } from '../config/config-number';

/**
 * Résultat d'un géocodage inverse : le repère texte que le CRM attend.
 *
 * `ville` / `wilaya` peuvent être `null` **ensemble** — un point que Nominatim
 * ne connaît pas (mer, zone non cartographiée) reste une réponse valide, pas
 * une panne (règle #10 : « géocodé, sans résultat » ≠ « échec »).
 */
export interface GeoReverseResult {
  ville: string | null;
  wilaya: string | null;
}

/** echango-geo injoignable, timeout, ou réponse non exploitable. */
export class GeoUnavailableError extends Error {
  constructor(cause: string) {
    super(`echango-geo injoignable : ${cause}`);
    this.name = 'GeoUnavailableError';
  }
}

/**
 * Client HTTP du service transverse `echango-geo` (Nominatim auto-hébergé).
 *
 * ── Pourquoi ce dépôt appelle un service et ne géocode pas lui-même ────────
 *
 * La décision 6 du `docs/PLAN_BASCULE_GEO.md` interdisait tout géocodeur dans
 * ce backend. Elle est **rouverte pour l'inverse côté serveur uniquement** :
 * le parcours client ne gagne aucune recherche de lieu, mais la position d'un
 * commerçant est désormais résolue en `ville`/`wilaya` **ici**, au moment où
 * elle est posée (`CommercantService.setPosition` est le seul écrivain de
 * `latitude`/`longitude`), via `echango-geo`. Le CRM Odoo se contente
 * désormais de lire `ville`/`wilaya` du snapshot, au lieu de reverse-géocoder
 * lui-même contre Nominatim (cron 15 min, lots, gestion du 429).
 *
 * ── `fetch` et non un client HTTP ─────────────────────────────────────────
 *
 * Le dépôt n'a pas de dépendance HTTP (voir `crm-push.service.ts`, qui pousse
 * au CRM avec `fetch`). On reste sur `fetch` global (Node 22) et
 * `AbortController` pour le délai.
 *
 * ── Frontière d'accès ─────────────────────────────────────────────────────
 *
 * `echango-geo` n'est pas exposé publiquement : joignable seulement sur le
 * réseau Docker `echango_network`, et exige un jeton partagé dans
 * `X-Internal-Token`.
 */
@Injectable()
export class GeoClientService {
  private readonly logger = new Logger(GeoClientService.name);
  private readonly baseURL: string;
  private readonly token: string;
  private readonly timeoutMs: number;

  constructor(private readonly config: ConfigService) {
    this.baseURL = (
      this.config.get<string>('GEO_SERVICE_URL') || 'http://geo-api:3000'
    ).replace(/\/+$/, '');
    this.token = (this.config.get<string>('GEO_INTERNAL_TOKEN') || '').trim();
    this.timeoutMs = configNumber(
      this.config.get('GEO_HTTP_TIMEOUT_MS'),
      8000,
      'GEO_HTTP_TIMEOUT_MS',
      { minimum: 500, maximum: 60000 },
    );
  }

  /**
   * Point → `ville` / `wilaya`.
   *
   * Lève `GeoUnavailableError` si `echango-geo` est injoignable ou répond en
   * erreur — l'appelant décide quoi en faire (`setPosition` sauve quand même
   * la position et laisse le reconcile reprendre). Ne lève **pas** pour un
   * point inconnu : rend `{ ville: null, wilaya: null }`.
   */
  async reverse(latitude: number, longitude: number): Promise<GeoReverseResult> {
    const url =
      `${this.baseURL}/v1/geocode/reverse` +
      `?lat=${encodeURIComponent(latitude)}&lon=${encodeURIComponent(longitude)}`;

    const controller = new AbortController();
    const minuteur = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const reponse = await fetch(url, {
        headers: { 'X-Internal-Token': this.token },
        signal: controller.signal,
      });
      if (!reponse.ok) {
        throw new GeoUnavailableError(`HTTP ${reponse.status}`);
      }
      const data = (await reponse.json()) as {
        city?: string | null;
        province?: string | null;
      };
      return {
        ville: nonVide(data?.city),
        wilaya: nonVide(data?.province),
      };
    } catch (error) {
      if (error instanceof GeoUnavailableError) {
        this.logger.warn(`reverse (${latitude},${longitude}) : ${error.message}`);
        throw error;
      }
      const cause =
        (error as Error).name === 'AbortError'
          ? `timeout ${this.timeoutMs}ms`
          : (error as Error).message;
      this.logger.warn(`reverse (${latitude},${longitude}) : ${cause}`);
      throw new GeoUnavailableError(cause);
    } finally {
      clearTimeout(minuteur);
    }
  }

  /** Sonde de joignabilité — rapporte, ne lève jamais. */
  async ping(timeoutMs = 2500): Promise<{ reachable: boolean }> {
    const controller = new AbortController();
    const minuteur = setTimeout(() => controller.abort(), timeoutMs);
    try {
      await fetch(`${this.baseURL}/health`, { signal: controller.signal });
      return { reachable: true };
    } catch {
      return { reachable: false };
    } finally {
      clearTimeout(minuteur);
    }
  }
}

function nonVide(v: unknown): string | null {
  return typeof v === 'string' && v.trim().length > 0 ? v : null;
}

import { Transform } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDefined,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  MaxLength,
  ValidateIf,
} from 'class-validator';
import { Categorie } from '../../common/enums/categorie.enum';
import { PaginationQueryDto } from '../../common/pagination/pagination-query.dto';
import { versNombre } from '../../common/transforms/vers-nombre';

/**
 * Tri de la liste client. `recent` est le défaut historique (favoris
 * d'abord, puis les plus récemment publiées) : ne jamais changer la valeur
 * par défaut, un client existant qui n'envoie pas ce paramètre doit garder
 * exactement le même ordre qu'avant.
 *
 * `discount` alimente le bandeau "Top promos" de l'accueil : trier côté
 * client ne donnerait que les meilleures réductions *de la page chargée*,
 * pas les meilleures tout court.
 */
export enum PromoSortOrder {
  RECENT = 'recent',
  DISCOUNT = 'discount',
}

export class ListPromoQueryDto extends PaginationQueryDto {
  /**
   * Jusqu'à 4 communes (décision produit 2026-07-12, pensée pour les
   * grandes villes comme Alger où les communes sont accolées — une promo
   * dans l'une intéresse un client dans la voisine). Plafond imposé ici,
   * pas seulement côté app : une garde uniquement client se contourne en
   * appelant l'API directement.
   */
  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(4)
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  communeIds?: string[];

  @IsOptional()
  @IsEnum(Categorie)
  categorie?: Categorie;

  /** Commerçants favoris (stockage local client, specs §3.1) — affichés en priorité. */
  @IsOptional()
  @IsArray()
  @IsUUID(undefined, { each: true })
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.split(',').filter(Boolean) : value,
  )
  favoriteIds?: string[];

  /**
   * Recherche libre sur la description de la promo et le nom du commerce
   * (barre de recherche de l'accueil). Plafonnée en longueur : une chaîne
   * arbitrairement longue dans un `ILIKE '%…%'` non indexé est un vecteur
   * de charge inutile sur un endpoint public.
   */
  @IsOptional()
  @IsString()
  @MaxLength(80)
  @Transform(({ value }: { value: unknown }) =>
    typeof value === 'string' ? value.trim() : value,
  )
  search?: string;

  /**
   * Restreint à un commerce donné — alimente « Autres promos du magasin »
   * sur la fiche promo, sans nouvel endpoint.
   */
  @IsOptional()
  @IsUUID()
  commercantId?: string;

  /**
   * Point autour duquel chercher (bascule géographique, 2026-08-12).
   *
   * ⚠️ **Ce n'est pas « la position du client ».** C'est le point qu'il a
   * **enregistré lui-même**, sur la carte ou après s'être centré via le GPS —
   * la distinction est juridique autant que technique, et elle est ce qui
   * permet d'affirmer aux deux stores que l'app ne collecte pas de
   * localisation de capteur (voir `docs/PLAN_BASCULE_GEO.md` §2.1). Rien
   * n'oblige ce point à être là où le client se trouve.
   *
   * Absent, le serveur applique son propre défaut (`GET /promo/config`) —
   * **sauf** si la requête porte déjà un périmètre explicite (`communeIds` ou
   * `commercantId`), auquel cas aucun filtre géographique ne s'applique. Sans
   * cette exception, l'app déjà installée (qui envoie `communeIds` de Djelfa)
   * verrait ses résultats croisés avec un rayon autour du point par défaut, et
   * n'afficherait plus rien.
   *
   * Les deux vont ensemble : `@ValidateIf` rend chacune obligatoire dès que
   * l'autre est là. Une latitude seule est une requête cassée, pas une
   * requête sans position — et la traiter comme une absence serait un défaut
   * silencieux (règle #29).
   */
  @ValidateIf(
    (o: ListPromoQueryDto) =>
      o.latitude !== undefined || o.longitude !== undefined,
  )
  @IsDefined()
  @Transform(versNombre)
  @IsLatitude()
  latitude?: number;

  @ValidateIf(
    (o: ListPromoQueryDto) =>
      o.latitude !== undefined || o.longitude !== undefined,
  )
  @IsDefined()
  @Transform(versNombre)
  @IsLongitude()
  longitude?: number;

  /**
   * Rayon de recherche, en kilomètres. Absent, celui de `GET /promo/config`.
   *
   * ⚠️ **Aucun `@Max` ici, et c'est délibéré** : le plafond réel est
   * `CLIENT_MAX_RADIUS_KM`, une valeur de configuration. L'écrire aussi dans ce
   * DTO en ferait une seconde source qui divergerait au premier changement de
   * `.env` (règle #32, cas fondateur du « Plafond de 5 promos » recopié dans
   * les `.arb`). Le refus est donc prononcé par le service, contre la valeur
   * effective.
   *
   * `@IsNumber()` refuse déjà `NaN` et `Infinity` par défaut — ce qui, avec
   * `versNombre`, ferme aussi le cas `?radiusKm=` (règle #34 : établir que
   * c'est un nombre fini, jamais le supposer).
   */
  @IsOptional()
  @Transform(versNombre)
  @IsNumber()
  @IsPositive()
  radiusKm?: number;

  /**
   * Ne renvoyer **que** les favoris, et sans aucun cadrage géographique.
   *
   * ⚠️ Un favori est un choix explicite du client : rien ne justifie qu'une
   * règle de proximité le lui retire. Le filtre était purement local — appliqué
   * aux pages déjà chargées — ce qui marchait tant que la fenêtre valait quatre
   * communes ; avec un rayon de 5 km, **un favori posé sur un commerce à 8 km
   * disparaissait de l'onglet sans un mot**. Un élément qui s'évapore sans
   * erreur ni message est exactement la classe de défaut que ce dépôt traque
   * (R7 du plan de bascule).
   */
  @IsOptional()
  @Transform(
    ({ value }: { value: unknown }) => value === 'true' || value === true,
  )
  @IsBoolean()
  favoritesOnly?: boolean;

  @IsOptional()
  @IsEnum(PromoSortOrder)
  sort?: PromoSortOrder;
}

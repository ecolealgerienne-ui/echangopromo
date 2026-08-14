FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
# ⚠️ **Épinglé le 2026-08-14, et ce n'est pas cosmétique.** 12 colonnes du
# schéma sont en `timestamp without time zone` ; node-postgres sérialise un
# paramètre `Date` dans le fuseau du PROCESSUS, et Postgres jette l'offset. Le
# fuseau de Node décale donc silencieusement toute comparaison de date.
#
# Mesuré sur le poste de développement (WSL, Europe/Paris) : la fenêtre glissante
# de 24 h du plafond anti-abus n'en faisait que **22** — l'anti-abus fuyait de
# 2 h par cycle, et l'API servait `createdAt` 2 h dans le passé.
#
# En production le décalage était déjà nul, mais par ACCIDENT : `node:22-alpine`
# n'a pas de `/etc/localtime`, donc Node tombait sur UTC. Rien ne le tenait —
# poser `TZ=Africa/Algiers` pour des journaux lisibles rallumait le défaut sans
# un mot, et un fuseau à l'OUEST d'UTC produirait cette fois de faux refus.
# Cette ligne transforme un accident en invariant (règle 30).
#
# Le remède de fond reste la migration des 12 colonnes en `timestamptz`, qui
# rendrait la question sans objet.
ENV TZ=UTC
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
EXPOSE 3000
# Exécution sous l'utilisateur non privilégié `node` fourni par l'image
# (uid 1000) plutôt qu'en root (durcissement, rapport pentest 2026-08-05 §7).
# Les artefacts (node_modules, dist) sont copiés en root mais restent
# lisibles par tous ; `node` n'a besoin que de les lire, la migration écrit
# en base et non sur le disque.
USER node
# Migrations avant démarrage — schéma géré uniquement par des migrations
# versionnées, plus par `synchronize` (voir src/data-source.ts).
CMD ["sh", "-c", "npx typeorm migration:run -d dist/data-source.js && node dist/main"]

FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
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

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
# Migrations avant démarrage — schéma géré uniquement par des migrations
# versionnées, plus par `synchronize` (voir src/data-source.ts).
CMD ["sh", "-c", "npx typeorm migration:run -d dist/data-source.js && node dist/main"]

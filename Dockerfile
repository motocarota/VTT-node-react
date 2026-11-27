# syntax=docker/dockerfile:1

# --- build: dipendenze complete, client Vite e server in un unico bundle ---
FROM node:24-slim AS build
WORKDIR /src
RUN npm install -g pnpm@10.12.3

# prima solo i manifest, così lo strato delle dipendenze resta in cache finché non cambiano
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/
COPY apps/client/package.json apps/client/
COPY packages/shared/package.json packages/shared/
RUN pnpm install --frozen-lockfile

COPY . .
ARG VTT_RELEASE=docker
RUN VITE_RELEASE="$VTT_RELEASE" pnpm build && pnpm --filter @vtt/server bundle

# --- runtime: solo Node, il bundle del server e il client compilato ---
FROM node:24-slim
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8080 \
    VTT_DATA_DIR=/data
WORKDIR /app
# index.ts ricava la radice come ../../.. rispetto a sé: la struttura apps/... va mantenuta
COPY --from=build /src/apps/server/dist/index.mjs apps/server/dist/index.mjs
COPY --from=build /src/apps/client/dist apps/client/dist
ARG VTT_RELEASE=docker
RUN echo "$VTT_RELEASE" > RELEASE

VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/server-info').then(r=>process.exit(r.ok?0:1),()=>process.exit(1))"
CMD ["node", "apps/server/dist/index.mjs"]

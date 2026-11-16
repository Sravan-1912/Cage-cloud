# Render web service: builds the console and serves it with nginx, proxying /api and /agent to the private API service.
# Build context: repository root. The nginx image runs envsubst over /etc/nginx/templates/*.template at startup,
# substituting ${PORT} (set by Render) and ${API_UPSTREAM} (the private API host, wired in render.yaml).
FROM node:22-alpine AS build
WORKDIR /src
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /src/dist /usr/share/nginx/html
# Template (not a final conf): nginx's entrypoint runs envsubst → /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/conf.d/default.conf
COPY infrastructure/nginx/nginx.render.conf.template /etc/nginx/templates/default.conf.template

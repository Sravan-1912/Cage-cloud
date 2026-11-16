# All-in-one web service for Render's free tier (no private services allowed): ONE uvicorn process serves the console
# SPA, the /api and /agent channels, and the RDP-relay WebSockets on a single public HTTPS origin. uvicorn[standard]
# handles WebSockets natively, so no nginx is needed.
#
# Build context: the repository ROOT (so it can see both frontend/ and backend/).

# 1) Build the React console
FROM node:22-alpine AS frontend
WORKDIR /src
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ .
RUN npm run build

# 2) Backend image that also serves the built SPA
FROM python:3.13-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 SPA_DIR=/app/spa
WORKDIR /app
RUN useradd --system --uid 10001 --home /app cage
COPY backend/requirements.txt .
RUN pip install -r requirements.txt
COPY --chown=cage:cage backend/app ./app
COPY --chown=cage:cage backend/migrations ./migrations
COPY --chown=cage:cage backend/alembic.ini .
COPY --from=frontend --chown=cage:cage /src/dist ./spa
# Device CA, command-signing and OIDC keys live here (ephemeral on free tier; add a persistent disk to keep them).
RUN mkdir -p /app/var /app/anchors && chown cage:cage /app/var /app/anchors && chmod 700 /app/var /app/anchors
USER cage
# Render sets $PORT. Run migrations, then serve everything (SPA + API + agent + WS relay) from one uvicorn.
CMD ["sh", "-c", "alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --proxy-headers --forwarded-allow-ips '*' --no-server-header"]

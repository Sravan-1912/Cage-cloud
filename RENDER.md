# Deploy Antiquarian's Cage on Render (plug-and-play)

This folder is a clean, Render-ready copy of the project. It deploys the console + API on one public HTTPS origin, so
admins can sign in (**email + password**) and endpoints on **any network** can enrol and be managed — including
**cross-network RDP**, which is relayed through this backend (both sides dial out over WebSocket, no VPN).

> **Honest scope.** This is a **hosted demo / friend-testing** deployment. It runs with `ALLOW_EDGE_TLS=true`, which
> turns **off the agent mTLS** layer (Render terminates TLS at its edge and can't pass client certs). Every agent
> request is still **cryptographically signed** (timestamp + nonce + body hash + device key), so it is authenticated —
> just without the extra mTLS defense-in-depth. For the fully-hardened design (mTLS on :8443) use a VPS instead
> (`documentation/13-cloud-deployment.md`). Also: Render's **free tier sleeps when idle** (cold starts, brief agent
> gaps), and the device CA lives on the API's ephemeral disk — if the API redeploys, agents must re-enrol (fine for a
> demo; add a Render persistent disk at `/app/var` to keep it).

## What gets created
`render.yaml` is a **Blueprint** that creates three things: a **Postgres** database, a **Key Value (Redis)** instance,
and one **public web service** (`cage-web`) — the FastAPI backend serving the console SPA **and** `/api`, `/agent` and
the RDP-relay WebSockets on one HTTPS origin. (Render's free plan has no private services, so there is no separate
API/nginx split — `uvicorn` serves everything.)

## Steps

### 1. Put this folder in a GitHub repo
Render deploys from Git. Either push this folder to a new repo, or use your existing repo (the `render.yaml` already
points at `https://github.com/Sravan-1912/Antiquarian-s-cage` — change the two `repo:` lines if you fork it).

```bash
cd /d/plug-and-play
git init && git add -A && git commit -m "Render deploy"
# create a repo on github.com, then:
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

### 2. Generate the secrets (keep them somewhere safe)
```bash
python infrastructure/scripts/generate_secrets.py
```
You need: `DATA_ENCRYPTION_KEY`, `AUDIT_HMAC_KEY` (must differ), and a `DEVICE_CA_KEY_PASSPHRASE` (any 24+ char string).

### 3. Create the Blueprint on Render
1. Sign in at **render.com** → **New → Blueprint**.
2. Connect the GitHub repo. Render reads `render.yaml` and shows the three services (Postgres, Redis, `cage-web`).
3. When prompted (or afterward, on **cage-web → Environment**), fill the `sync: false` values:
   - `DATA_ENCRYPTION_KEY`, `AUDIT_HMAC_KEY`, `DEVICE_CA_KEY_PASSPHRASE` → from step 2.
   - For `PUBLIC_BASE_URL` / `ALLOWED_ORIGINS`, enter placeholder `https://cage-web.onrender.com` and
     `["https://cage-web.onrender.com"]` now, and correct them in step 5 once you know the real URL.
4. Click **Apply** / **Create**. Render builds and deploys. `cage-web` runs `alembic upgrade head` at startup.

### 4. Get your public URL
After deploy, **cage-web** has a URL like `https://cage-web-xxxx.onrender.com`. That's your app.

### 5. Set the base URL, then redeploy
On **cage-web → Environment**, set:
- `PUBLIC_BASE_URL` = `https://cage-web-xxxx.onrender.com`
- `ALLOWED_ORIGINS` = `["https://cage-web-xxxx.onrender.com"]`

Save → it redeploys. (Required so the origin check passes.)

### 6. Bootstrap the Super Admin
Open `https://cage-web-xxxx.onrender.com/` → **Set up your organisation** → enter org name, your name, email and a
**password** (≥12 chars, three of lowercase/uppercase/digits/symbols). You're signed in. Locked out later? Use the API
Shell: `python -m app.recover <email>` prints a one-time temporary password.

## Add a friend
- **As a console admin:** Administrators → **Create administrator** → it shows a **temporary password once** → send the
  email + that password to your friend (any trusted channel). They sign in and are forced to set their own password.
  Super Admins can also **Create organisation** (a separate org with its own Super Admin).
- **As a managed endpoint (their laptop):**
  1. In the console: **Endpoints → Enrol an endpoint** → copy the token.
  2. Build the agent (`agent/installer/build.ps1` → `cage-agent.exe`) or run it from source, and send your friend the
     agent + this command (no `--allow-insecure-localhost` needed — Render has a real cert):
     ```
     cage-agent enroll --server https://cage-web-xxxx.onrender.com --token <TOKEN>
     cage-agent run
     ```
  3. Their laptop appears under **Endpoints** with live inventory, compliance and remote actions — **from any network**,
     because the agent dials out to this backend.

## Remote desktop (RDP) across networks
RDP is relayed through this backend, so it works between different networks with no VPN. To use it:
1. **Deploy the agent in the user's interactive session** on the endpoint (not only as the session-0 service) — the
   mandatory on-screen banner and the tunnel run there.
2. **Use the installed desktop app as your console**, pointed at this backend:
   `CAGE_REMOTE_BACKEND_URL=https://cage-web-xxxx.onrender.com` (a plain browser can't open the local tunnel + `mstsc`,
   so the **Connect** button there only explains that the app is required).
3. On an endpoint's page: **Remote desktop** starts an unattended session (visible banner on the endpoint); **Connect**
   opens `mstsc` tunnelled through this backend to the endpoint.

> Keep **one** API instance (`numInstances: 1` in `render.yaml`): the relay pairs a session's two tunnels in one
> process. Not verified on real two-network hardware — test on isolated VMs first.

## If something fails on first deploy
- **DB errors / migrations** → Render's Postgres URL is `postgresql://…`; the app auto-rewrites it to
  `postgresql+psycopg://` (see `backend/app/core/database.py:_normalize_db_url`). Check **cage-web → Logs**.
- **"Origin not allowed" at sign-in** → `ALLOWED_ORIGINS` doesn't exactly match the real web URL (step 5); fix + redeploy.
- **Service won't start** → `cage-web` uses Render's `$PORT` (via the Dockerfile `CMD`); don't hardcode a port.
- **"Origin not allowed" at sign-in** → `ALLOWED_ORIGINS` doesn't exactly match the web URL (step 5); fix and redeploy.
- **Port binding** → the API uses Render's `$PORT` (via `dockerCommand` in `render.yaml`); don't hardcode a port.

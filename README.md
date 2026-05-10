# skrivDET Website

Vite/React marketing site for skrivDET by Kvasetech AS, served in production by Node.js + Express. Express serves the built frontend from `dist/` and handles the contact form at `POST /api/contact`.

## What Runs In Production

Public URLs:

- `https://skrivdet.no/`
- `https://www.skrivdet.no/`

Runtime:

- Server: `192.168.222.171` (`ai`)
- Container: `skrivdet`
- Host port: `8080`
- Container port: `3000`
- Docker mapping: `0.0.0.0:8080->3000/tcp`
- Restart policy: `unless-stopped`

APISIX routes on `192.168.222.171` forward public traffic to the container:

- `skrivdet-no-website`: `skrivdet.no` and `www.skrivdet.no`, `/` and `/*`, upstream `192.168.222.171:8080`
- `skrivdet-no-website-prefixed-assets`: `/skrivdet/assets/*`, upstream `192.168.222.171:8080`
- `skrivdet-acme-http01`: ACME challenge route, upstream `192.168.222.171:8088`

Contact form mail:

- Endpoint: `POST /api/contact`
- SMTP relay: `192.168.222.12:25`
- Recipient: `post@skrivdet.no`
- Sender: `post@skrivdet.no`
- Visitor email is used as `Reply-To`

Operational credentials and keys are documented in local-only `SECRETS.md`. That file is ignored by git and Docker.

## Project Structure

- `index.html` - Vite entry file
- `src/App.jsx` - React app, routes, and page content
- `src/main.jsx` - React bootstrap
- `src/styles.css` - imports the root stylesheet into the Vite app
- `styles.css` - shared site styling
- `server.js` - Express server and contact-form mail endpoint
- `public/assets/` - images, logos, screenshots, and app icons used by the site
- `Dockerfile` - production image build
- `.env.example` - documented runtime environment variables
- `.nvmrc` - Node major version for local development
- `.github/workflows/docker-publish.yml` - GHCR publish workflow

## Fresh MacBook Setup

1. Install prerequisites:

```bash
xcode-select --install
brew install git node
```

If you use `nvm`, run this instead of relying on the Homebrew Node version:

```bash
nvm install
nvm use
```

2. Clone the repository:

```bash
git clone https://github.com/kjellmagne/skrivdet-website.git
cd skrivdet-website
```

3. Install dependencies:

```bash
npm ci
```

4. Create optional local environment:

```bash
cp .env.example .env
```

The defaults in `server.js` already match production. The app does not load `.env` automatically; use it as a reference for shell exports, `docker --env-file`, or deployment settings.

5. Copy local-only operational files from the old machine if this MacBook will deploy or administer the server:

```bash
SECRETS.md
~/.ssh/codex_mailcow_kvasetech
~/.ssh/codex_mailcow_kvasetech.pub
~/.ssh/kvasetech_github_codex_ed25519
~/.ssh/kvasetech_github_codex_ed25519.pub
~/.ssh/config
```

After copying private keys, fix permissions:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/codex_mailcow_kvasetech ~/.ssh/kvasetech_github_codex_ed25519
chmod 644 ~/.ssh/*.pub
```

6. Verify GitHub access:

```bash
ssh -T github-kvasetech-codex
git status
```

7. Verify server SSH access if this MacBook will deploy:

```bash
ssh -i ~/.ssh/codex_mailcow_kvasetech rootadmin@192.168.222.171 'hostname'
```

## Local Development

Run the Vite dev server:

```bash
npm run dev
```

Build the frontend:

```bash
npm run build
```

Run the production Express server locally:

```bash
npm run build
npm start
```

The production server serves `dist/`, so run `npm run build` before `npm start`. It listens on `PORT` or `3000` by default.

Runtime environment variables:

- `PORT`
- `SMTP_HOST`
- `SMTP_PORT`
- `SMTP_SECURE`
- `SMTP_REJECT_UNAUTHORIZED`
- `MAIL_TO`
- `MAIL_FROM`

Defaults:

- `SMTP_HOST=192.168.222.12`
- `SMTP_PORT=25`
- `MAIL_TO=post@skrivdet.no`
- `MAIL_FROM=post@skrivdet.no`

## Verification

Build check:

```bash
npm run build
```

Production dependency audit:

```bash
npm audit --omit=dev
```

Local Express smoke test:

```bash
npm run build
PORT=3001 npm start
curl -I http://127.0.0.1:3001/
curl -i -X POST http://127.0.0.1:3001/api/contact \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Test","lastName":"User","phone":"","email":"test@example.com"}'
```

The contact test sends a real email through the relay when `SMTP_HOST` is reachable.

## Docker

Build the image locally:

```bash
docker build -t skrivdet:local .
```

Run it locally:

```bash
docker run --rm -p 8080:3000 skrivdet:local
```

Then open `http://localhost:8080`.

## Deploy On The Server

The live server currently runs a locally built image, so deployment does not depend on GHCR availability.

From this workstation:

```bash
rm -rf /tmp/skrivdet-deploy /tmp/skrivdet-deploy.tar.gz
mkdir -p /tmp/skrivdet-deploy
git archive --format=tar HEAD | tar -x -C /tmp/skrivdet-deploy
tar -C /tmp -czf /tmp/skrivdet-deploy.tar.gz skrivdet-deploy
scp -i ~/.ssh/codex_mailcow_kvasetech /tmp/skrivdet-deploy.tar.gz rootadmin@192.168.222.171:/tmp/skrivdet-deploy.tar.gz
```

On `192.168.222.171`:

```bash
rm -rf /tmp/skrivdet-deploy
tar -xzf /tmp/skrivdet-deploy.tar.gz -C /tmp
sudo docker build -t skrivdet:<commit-sha> -t skrivdet:latest /tmp/skrivdet-deploy
sudo docker stop skrivdet
sudo docker rm skrivdet
sudo docker run -d \
  --name skrivdet \
  --restart unless-stopped \
  -p 8080:3000 \
  -e SMTP_HOST=192.168.222.12 \
  -e SMTP_PORT=25 \
  -e MAIL_TO=post@skrivdet.no \
  -e MAIL_FROM=post@skrivdet.no \
  skrivdet:<commit-sha>
```

Verify production:

```bash
curl -I https://skrivdet.no/
curl -i -X POST https://skrivdet.no/api/contact \
  -H 'Content-Type: application/json' \
  -d '{"firstName":"Test","lastName":"User","phone":"","email":"test@example.com"}'
```

## GHCR Deployment

GitHub Actions publishes `ghcr.io/kjellmagne/skrivdet-website:latest` on pushes to `main`. The live server is currently using a locally built image, but the GHCR flow is kept available.

If using GHCR on the server:

```bash
docker pull ghcr.io/kjellmagne/skrivdet-website:latest
docker stop skrivdet
docker rm skrivdet
docker run -d \
  --name skrivdet \
  --restart unless-stopped \
  -p 8080:3000 \
  -e SMTP_HOST=192.168.222.12 \
  -e SMTP_PORT=25 \
  -e MAIL_TO=post@skrivdet.no \
  -e MAIL_FROM=post@skrivdet.no \
  ghcr.io/kjellmagne/skrivdet-website:latest
```

If the package stays private, the server must log in first:

```bash
echo "<github_token>" | docker login ghcr.io -u kjellmagne --password-stdin
```

## Cleanup Notes

Generated and local-only paths should stay out of git:

- `node_modules/`
- `dist/`
- `.env`
- `.env.local`
- `SECRETS.md`

The old nginx runtime has been removed. Production now runs Express directly in Node, so there is no `nginx.conf` in the repo.

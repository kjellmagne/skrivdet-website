# skrivDET website

Vite/React rebuild of the Wix Studio landing page at:

`https://kjellmagnegabriels6.wixstudio.com/my-site-1?rc=test-site`

## Files

- `index.html` – Vite entry file
- `src/App.jsx` – React app and routes
- `src/main.jsx` – React bootstrap
- `styles.css` – shared site styling used by React
- `public/assets/` – downloaded media from the Wix page
- `Dockerfile` – production image build
- `.github/workflows/docker-publish.yml` – GHCR publish workflow

## Notes

- Store download buttons keep the same placeholder target used on the published Wix page.
- Privacy and accessibility pages now live as React routes because the linked Wix pages returned 404 on `2026-04-26`.

## Run locally

- `npm install`
- `npm run dev`
- `npm run build`
- `npm run preview`

## Docker

Build the image locally:

- `docker build -t skrivdet:local .`

Run it locally:

- `docker run --rm -p 8080:80 skrivdet:local`

Then open `http://localhost:8080`.

## Pull on a server

After GitHub Actions publishes the image, pull it from GHCR:

- `docker pull ghcr.io/kjellmagne/skrivdet:latest`
- `docker run -d --name skrivdet -p 80:80 --restart unless-stopped ghcr.io/kjellmagne/skrivdet:latest`

If the package stays private, the server must log in first:

- `echo "<github_token>" | docker login ghcr.io -u kjellmagne --password-stdin`

If you want anonymous pulls, change the published package visibility to public in GitHub after the first image push.

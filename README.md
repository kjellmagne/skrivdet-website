# skrivDET website

Vite/React site for skrivDET by Kvasetech AS.

## Files

- `index.html` – Vite entry file
- `src/App.jsx` – React app and routes
- `src/main.jsx` – React bootstrap
- `server.js` – Express server and contact-form mail endpoint
- `styles.css` – shared site styling used by React
- `public/assets/` – images, logos and product screenshots used by the site
- `Dockerfile` – production image build
- `.github/workflows/docker-publish.yml` – GHCR publish workflow

## Notes

- Store download buttons currently point to the main page until the final store URLs are ready.
- Privacy and accessibility pages live as React routes within the site.

## Run locally

- `npm install`
- `npm run dev`
- `npm run build`
- `npm start`
- `npm run preview`

The production server listens on `PORT` or `3000` by default. Contact form delivery defaults to:

- `SMTP_HOST=192.168.222.12`
- `SMTP_PORT=25`
- `MAIL_TO=post@skrivdet.no`
- `MAIL_FROM=post@skrivdet.no`

## Docker

Build the image locally:

- `docker build -t skrivdet:local .`

Run it locally:

- `docker run --rm -p 8080:3000 skrivdet:local`

Then open `http://localhost:8080`.

## Pull on a server

After GitHub Actions publishes the image, pull it from GHCR:

- `docker pull ghcr.io/kjellmagne/skrivdet:latest`
- `docker run -d --name skrivdet -p 80:3000 --restart unless-stopped ghcr.io/kjellmagne/skrivdet:latest`

If the package stays private, the server must log in first:

- `echo "<github_token>" | docker login ghcr.io -u kjellmagne --password-stdin`

If you want anonymous pulls, change the published package visibility to public in GitHub after the first image push.

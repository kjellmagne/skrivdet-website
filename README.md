# Ulfy local clone

Vite/React rebuild of the Wix Studio page at:

`https://kjellmagnegabriels6.wixstudio.com/my-site-1?rc=test-site`

## Files

- `index.html` – Vite entry file
- `src/App.jsx` – React app and routes
- `src/main.jsx` – React bootstrap
- `styles.css` – shared site styling used by React
- `public/assets/` – downloaded media from the Wix page

## Notes

- Store download buttons keep the same placeholder target used on the published Wix page.
- Privacy and accessibility pages now live as React routes because the linked Wix pages returned 404 on `2026-04-26`.

## Run locally

- `npm install`
- `npm run dev`
- `npm run build`
- `npm run preview`

# UPORTAL Admin

Vue 3 + Vite admin UI for UPORTAL.

## Run

From repository root:

```bash
docker compose up --build
```

Or from this directory when Node/npm are available:

```bash
npm install
npm run dev
```

The app talks to the UPORTAL admin API through `src/api/uportalApi.js`.

## Current Focus

The current work area is publication draft editing and publishing:

- `src/pages/PublicationsPage.vue`
- `src/publications/LinkEditorModal.vue`
- `src/publications/forms/*`
- `src/store/index.js`

The next implementation step is wiring drafts to real publish/upload endpoints.

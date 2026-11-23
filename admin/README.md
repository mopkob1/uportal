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

## Optional Site Integration

When a commercial site session is active and the account has Telegram bound,
publication rows show a Send icon before the short URL copy control. It sends
the short URL to the signed-in account through `POST /api/site/telegram/send-link`.
This action is available on all plans and is independent of link activity
notifications. Standalone CE installations do not show the control.

## Current Focus

The current work area is publication draft editing and publishing:

- `src/pages/PublicationsPage.vue`
- `src/publications/LinkEditorModal.vue`
- `src/publications/forms/*`
- `src/store/index.js`

The next implementation step is wiring drafts to real publish/upload endpoints.

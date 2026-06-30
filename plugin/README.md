# UPORTAL Plugin

Thunderbird WebExtension for inserting UPORTAL links into email drafts and
publishing tracked links/pixels before sending.

## Contents

```text
plugin/
  uportal-link-inserter-pixel-switch.xpi  Original extension package.
  uportal-link-inserter.xpi               Rebuilt package from source/.
  source/                                Extracted extension source.
```

The XPI was extracted into `source/` so the extension code can be reviewed,
versioned and changed together with the rest of UPORTAL.

## What It Does

- Loads a UPORTAL dictionary from the configured admin API.
- Shows dictionary redirect links in the Thunderbird compose action popup.
- Inserts selected links into the message as placeholders:
  `[[uportal:<dictionary_id>]]`.
- On `compose.onBeforeSend`, publishes each placeholder as a UPORTAL
  `redirect`.
- Replaces placeholders with generated short URLs.
- Publishes a per-email `pixel` and appends a hidden tracking image.
- Supports a per-message switch: send this email without UPORTAL.

## Source Layout

```text
source/
  manifest.json
  background.js
  compose-script.js
  popup/
  options/
  confirm/
  fixtures/
  scripts/pack.sh
```

## Runtime Integration

The extension uses the same server contracts as the admin UI:

- `GET /api/admin/dictionary`
- `POST /api/admin/publish/redirect`
- `POST /api/admin/publish/pixel`

Authentication is sent with:

```text
X-User-Token: <token>
```

Shared contracts:

- `../docs/api-contract.md`
- `../docs/meta-contract.md`
- `../docs/events-contract.md`

## Packaging

From `plugin/source/`:

```bash
scripts/pack.sh
```

This writes:

```text
plugin/uportal-link-inserter.xpi
```

The currently supplied package is:

```text
plugin/uportal-link-inserter-pixel-switch.xpi
```

The rebuilt package matching the current source is:

```text
plugin/uportal-link-inserter.xpi
```

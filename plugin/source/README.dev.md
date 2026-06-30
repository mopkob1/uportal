# UPORTAL Link Inserter Source Notes

This directory contains the extracted source of
`../uportal-link-inserter-pixel-switch.xpi`.

## Extension

- Target: Thunderbird WebExtension.
- Manifest: `manifest_version: 2`.
- Extension id: `uportal-link-inserter@1qr.org`.
- Minimum Thunderbird/Gecko version: `102.0`.
- Version in XPI: read from `../../VERSION` by `scripts/pack.sh`.

## Main Files

- `manifest.json` - Thunderbird extension manifest.
- `background.js` - settings, dictionary loading, publish API calls,
  `compose.onBeforeSend` processing.
- `compose-script.js` - inserts HTML into the active compose editor.
- `popup/` - compose action popup for choosing dictionary links and toggling
  "send without UPORTAL".
- `options/` - extension settings UI.
- `confirm/` - fallback decision popup when UPORTAL publish fails.
- `scripts/pack.sh` - XPI packaging helper.

## Settings

Stored in `browser.storage.local`:

- `apiBase`, default `http://localhost:8080`.
- `pixelBaseUrl`, defaults to `apiBase` when unset.
- `userToken`.
- `dictionaryUrl`, default `http://localhost:8080/api/admin/dictionary`.
- `defaultMailFrom`, defaults to `no-reply@<api-base second-level domain>`.
- `defaultLinkText`, default `Открыть ссылку`.
- `pixelTokenPrefix`, default `mail-pixel`.

## Send Flow

1. User inserts dictionary links from the compose action popup.
2. Inserted links use placeholder URLs like `[[uportal:<id>]]`.
3. `background.js` intercepts `browser.compose.onBeforeSend`.
4. It creates one `publication_id` for the email:
   `mail-<timestamp>-<random>`.
5. Each redirect placeholder is published through
   `POST /api/admin/publish/redirect`.
6. The placeholder is replaced with the returned short URL.
7. A pixel is published through `POST /api/admin/publish/pixel`.
8. A 1x1 `<img data-uportal-pixel="1">` is appended to the body.

## Failure Behaviour

If UPORTAL publishing fails, the extension opens `confirm/confirm.html` and asks
whether to:

- send without UPORTAL, replacing placeholders with original dictionary URLs and
  removing old hidden pixel images;
- cancel sending and try to save the message as a draft.

The user decision times out after 120 seconds and defaults to cancel.

## Per-Message Disable

The popup checkbox "Отправить это письмо без UPORTAL" stores a flag by compose
tab id. On send, UPORTAL API calls are skipped, placeholders are replaced with
plain dictionary URLs, and no pixel is added.

## Known Limits

- The popup currently displays only dictionary items with `type === "redirect"`.
- The extension publishes `redirect` and `pixel`; it does not publish `page` or
  `download`.
- Dictionary normalization accepts several response shapes, but stable server
  shape should remain documented in `../../docs/api-contract.md`.

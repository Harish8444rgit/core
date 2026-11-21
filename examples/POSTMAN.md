# LinkForty Core — Postman collection

Import `examples/linkforty-core.postman_collection.json` into Postman (Import → File). Insomnia and Bruno also open Postman v2.1 collections.

The collection is one product journey, split into feature folders. Run the folders from top to bottom with the Collection Runner. Each create request writes ids into collection variables. Later requests read those variables. Folder **12 Cleanup** deletes what you created. Skip it if you want the rows left in PostgreSQL.

Start the server first (`examples/docker-compose.yml` or `examples/basic-server.ts`). It listens on port 3000.

## The one variable you set

| Variable | Default | What to put |
| --- | --- | --- |
| `localbase_url` | `http://localhost:3000` | Server origin, no trailing slash. Every request is `{{localbase_url}}/...`. |

Open the collection → Variables, change `localbase_url` if the server is not on your machine, and save.

## Variables the journey fills in

The collection pre-request script fills the empty ones once. Clear a value in the Variables tab to mint a new one on the next send.

| Variable | Who sets it | What it is |
| --- | --- | --- |
| `user_id` | First request, a new UUID | Tenant id. Dashboard routes take it as `?userId=`. The same id is used for the whole journey so lists only show your rows. Must be a UUID. |
| `template_id` | Create template (`id`) | Template to read, update, set as default, attach to a link, and delete. |
| `template_slug` | Create template (`slug`) | Public path `/:templateSlug/:shortCode` and the scoped SDK resolve. |
| `link_id` | Create link (`id`) | The campaign link. QR, analytics, debug simulate, and the final delete use it. |
| `short_code` | Create link (`short_code`) | Public code. Minted before create and sent as `customCode`, then overwritten with whatever the server stored. |
| `duplicate_link_id` | Duplicate link (`id`) | The clone. Cleanup deletes this first and leaves `link_id` for the rest of the journey. |
| `webhook_id` | Create webhook (`id`) | Webhook to read, update, test, and delete. |
| `webhook_secret` | Create webhook (`secret`) | HMAC secret. The receiver checks header `X-LinkForty-Signature`. The list endpoint does not return it. |
| `install_id` | Report install (`installId`) | Required by Track in-app event. |
| `play_install_id` | Android install request | Separate from `install_id`, so the event stays attached to the first install. |
| `device_id` | First request | Stand-in for IDFA / GAID. Sent on install. |
| `client_event_id` | First request | Idempotency key for the in-app event. Send Track in-app event twice: the second response has `duplicate: true`. Clear this variable to record a new event. |

## Variables you can edit to change the story

| Variable | Default | What it changes |
| --- | --- | --- |
| `webhook_receiver_url` | `https://httpbin.org/post` | Where webhook deliveries are POSTed. httpbin echoes the body so the test request has somewhere to land. |
| `days` | `7` | Analytics window (`?days=`). The server uses 30 if you omit it. Bot clicks are excluded. |
| `fp_tz` | `Asia/Kolkata` | Device timezone. Sent on the click as `?fp_tz=` and again in the install body. Worth 10 fingerprint points. |
| `fp_lang` | `en-IN` | Device language. Click query `fp_lang`, install body, and the `Accept-Language` header. Worth 10 points. The sample link only allows language `en`, so keep an English tag. |
| `fp_sw` / `fp_sh` | `390` / `844` | Screen size in pixels. Click queries `fp_sw` and `fp_sh`, and the install body. Together worth 10 points. |
| `ios_user_agent` | iPhone Safari | User-Agent for the click that the install should match, and for `install.userAgent`. Worth 30 points. |
| `android_user_agent` | Pixel 8 Chrome | Android redirect. Play Store URLs carry `lf_click=<click id>`. |
| `desktop_user_agent` | macOS Safari | Desktop redirect: website, or the launchpad page when there is no website. |
| `crawler_user_agent` | Facebook crawler | Social preview. Known bots get Open Graph HTML instead of a redirect. |
| `fingerprint` | empty | Paste `install_events.fingerprint_hash` from the database before Lookup attribution. The install response does not return this hash. Until you paste it, that request is a 404. |
| `install_referrer` | empty | Android Play referrer, for example `lf_click=<uuid>`. When set, the install requests send it and the match is that exact click (`attributionMethod: install_referrer`). |

## Folder order

| Folder | What you are proving |
| --- | --- |
| 01 Health | Process is up (`/health`). Postgres answers (`/health/ready`, 503 when it does not). |
| 02 Templates | Shared defaults. Saves `template_id` and `template_slug`. Set-default clears the previous default for this `user_id`. |
| 03 Links | The campaign link: create, list, get, update, duplicate. The short code does not change on update. Deletes are in folder 12. |
| 04 Public redirect | A tap. Follow-redirects is off so you see `302` and the `Location` header (or `200` HTML for a launchpad / interstitial). The iPhone request is the click the install should match. It sends the same User-Agent and `fp_*` values as the install. |
| 05 Social preview | `GET /:shortCode/preview`. **Not mounted** by `createServer()`. Register `previewRoutes` or this is 404. Folder 04 already returns the preview card when the User-Agent is a crawler. |
| 06 QR codes | PNG and SVG of the short URL. The body is an image. |
| 07 Analytics | Clicks from folder 04, over `{{days}}` days, for the tenant and for one link. |
| 08 Webhooks | Create, list, get (with secret), update, and a test delivery to `webhook_receiver_url`. |
| 09 Mobile SDK | Health, resolve (app already installed), install (deferred deep link), attribution lookup, in-app event. |
| 10 App association | Apple and Google domain files. 404 until `IOS_TEAM_ID`, `IOS_BUNDLE_ID`, `ANDROID_PACKAGE_NAME`, and `ANDROID_SHA256_FINGERPRINTS` are set. |
| 11 Debug | Dry-run a click without writing one, plus sample user agents, countries, and languages. **Not mounted** by `createServer()`. Register `debugRoutes`. The live stream is a WebSocket: New → WebSocket, then `ws://localhost:3000/api/debug/live?userId={{user_id}}&linkId={{link_id}}`. |
| 12 Cleanup | Delete the duplicate link, the webhook, the template, then the original link. |

## How an install gets matched to the click

Run **04 → Open short link as iPhone** before **09 → Report install**.

1. If `install_referrer` contains `lf_click=<id>`, that click wins. Confidence 100. Method `install_referrer`.
2. Otherwise the server scores clicks inside the link’s attribution window (this journey uses 168 hours):

| Signal | Points |
| --- | --- |
| IP address | 40 |
| User agent | 30 |
| Timezone | 10 |
| Language | 10 |
| Screen size | 10 |

A match needs **70 or more**. The same machine gives you IP (40) plus the shared User-Agent (30), which is already 70. The `fp_*` values add the rest. The server uses the connection IP, not a IP you put in the JSON body.

The install response tells you what happened: `attributed`, `attributionMethod` (`install_referrer`, `fingerprint`, or `none`), `confidenceScore`, `matchedFactors`, `competingLinks`, and `deepLinkData` (the in-app path and parameters). `attributed: false` means organic: no campaign link cleared the bar.

## Notes that save a failed run

- `userId` must be a UUID. The collection generates one. A value like `test-user` is rejected.
- Create link omits `templateId` when `template_id` is empty, so that request still works if you skipped templates.
- Do not send both `attributionWindowHours` and `attributionWindowMinutes`.
- `appScheme` must start with a lowercase letter and contain only lowercase letters, digits, `+`, `.`, or `-`.
- Country targeting is not set on the sample link. Localhost often has no country, and a country list would 404 the click. Add `countries` on the update request when you want to test that rule.
- Folders 05 and 11 return 404 on the default server. That means the plugin is not registered.

# Gemini proxy (`server/`) — dodging the Hong Kong geo-block

## Why

The Gemini Developer API rejects requests that originate from Hong Kong with
HTTP 400 `"User location is not supported for the API use."`. That's the
network origin's location, not the account's — so testing the app straight
from an HK phone/laptop always fails, no matter which key is used.

`~/git/event-calendar` works around the same restriction by letting its
Next.js API routes call Gemini server-side, from wherever Vercel happens to
run the function — see `src/lib/ai/client.ts` and its `GEMINI_BASE_URL`
override. That project doesn't pin a region itself; it just isn't running
from Hong Kong. `server/` in this repo takes the same idea one step further
and **pins the function to Tokyo (`hnd1`)** explicitly, so it's not left to
whichever region Vercel picks by default.

## Architecture

```
Flutter app (lib/services/gemini_service.dart)
  → POST $GEMINI_BASE_URL/v1beta/models/<model>:generateContent?key=<APP_TOKEN>
  → server/ (Vercel function, region hnd1 / Tokyo)
      - checks APP_TOKEN, model allow-list, body size, per-IP rate limit
      - forwards to https://generativelanguage.googleapis.com/... with the
        REAL Gemini key (x-goog-api-key header, never sent to the client)
      - returns Gemini's status + JSON body unchanged
  ← Gemini Developer API
```

The app needs **zero code changes** — `gemini_service.dart` already treats
`GEMINI_BASE_URL` and the `key` query param as opaque config. Once the proxy
is deployed, only `env/dev.json` changes:

- `GEMINI_BASE_URL` → the proxy's URL (no path suffix; `vercel.json`'s
  rewrite maps `/v1beta/...` at the root to the `api/v1beta/...` function).
- `GEMINI_API_KEY` → the proxy's `APP_TOKEN` (a random secret you mint below,
  **not** the real Google AI Studio key — that stays only in the proxy's
  Vercel env).

### Routing: rewrite vs. file-based dynamic route

`server/api/v1beta/models/[modelAction].ts` is a Vercel dynamic file route —
the segment `[modelAction]` captures the whole final path segment, e.g.
`gemini-3.5-flash:generateContent`, colon included. File routes are served
under `/api/...`, so `server/vercel.json` also has a rewrite:

```json
{ "source": "/v1beta/models/:modelAction", "destination": "/api/v1beta/models/:modelAction" }
```

so the app can hit `$GEMINI_BASE_URL/v1beta/models/...` (no `/api`) exactly
like it hits the real Gemini API today. Both paths reach the same handler.

**Why the colon in the path is safe**: not verified against a live
deployment in this change (deploying was out of scope). Verified offline
instead, against the actual routing engine Vercel uses. `@vercel/routing-utils` depends on
`path-to-regexp@6.1.0`; installing that version and running its `match()`
against the rewrite source confirms the colon in the *request path* is
matched as a literal character inside the `:modelAction` segment (colons are
only special in the *pattern template*, not in matched values):

```js
const { match } = require('path-to-regexp'); // v6.1.0, pinned by @vercel/routing-utils
match('/v1beta/models/:modelAction')('/v1beta/models/gemini-3.5-flash:generateContent')
// → { params: { modelAction: 'gemini-3.5-flash:generateContent' }, ... }
```

If the rewrite ever does misbehave in production, the file route still
answers directly at `.../api/v1beta/models/gemini-3.5-flash:generateContent`
— set `GEMINI_BASE_URL` to `https://<project>.vercel.app/api` as a fallback.

### Handler logic (`server/lib/proxy.ts`)

Pure, framework-free function `handleProxy(request, deps)` — no `@vercel/node`
types inside it, so vitest exercises it directly; `api/v1beta/models/[modelAction].ts`
is only a thin request/response adapter.

- **Method**: only `POST` is proxied; `OPTIONS` gets a CORS preflight reply
  (before any auth check, since preflight requests carry no key); anything
  else is a Gemini-shaped 404.
- **Model allow-list**: `<model>:generateContent` where `model` is in
  `ALLOWED_MODELS` (env, comma-separated; defaults to `gemini-3.8-flash,
  gemini-3.5-flash,gemini-3.1-flash-lite` — the app's cascade). Anything else
  → 404 `{error:{code,message,status}}`.
- **Auth**: `key` query param or `x-goog-api-key` header must equal
  `APP_TOKEN` (env), compared with `crypto.timingSafeEqual` over SHA-256
  hashes of both sides (so unequal-length inputs don't short-circuit the
  comparison) → else 401.
- **Body size cap**: 64 KB (via `Content-Length`, falling back to the
  serialized body) → 413.
- **Rate limit**: best-effort, 30 requests / 5 minutes per client IP
  (`x-forwarded-for`, first entry), **in-memory only** — it resets on cold
  start and is not shared across concurrent Vercel instances. It's an abuse
  guard, not a hard quota → 429, Gemini-shaped.
- **Forwarding**: `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`
  with `x-goog-api-key: <real key>`, the client's JSON body passed through
  unchanged, 25s timeout (→ 504 on timeout, 502 on other network failures).
  The upstream status and JSON body are returned **unchanged**, so the app's
  existing 429/503/404 cascade-and-retry logic keeps working untouched.
- **Logging**: only `model`, upstream `status`, and latency are logged —
  never the prompt or either key. Note: Vercel's own platform request logs
  will still show the full request URL, including the `?key=<APP_TOKEN>`
  query string — that's an accepted tradeoff of mirroring the app's existing
  contract (same as the real Gemini API takes `key` as a query param).
- **CORS**: `Access-Control-Allow-Origin: *`, methods `POST, OPTIONS`,
  headers `Content-Type, x-goog-api-key` — covers the Flutter *web* preview
  build calling from a browser origin.
- **`GET /api/health`** → `{ ok: true, region: process.env.VERCEL_REGION }`
  — use this to confirm the deployed region is `hnd1`.

## Tests

```
cd server && npm install && npm test
```

Used `npm` (found at `~/.nix-profile/bin/npm`, v10.9.7) — `npx`/`pnpm` also
work, nothing is npm-specific. 23 vitest cases in `test/proxy.test.ts` cover:
model allow-list (default + `ALLOWED_MODELS` override + disallowed
action), token check (query + header, missing/wrong), body size cap at/over
the limit, rate limiting (per-IP isolation, 429 after the cap, window reset),
OPTIONS/CORS, non-POST rejection, and upstream passthrough (mocked
`fetch`) for 200/400/503/timeout/network-failure — including a check that
the *app token* never appears in the URL sent upstream, only the real key in
a header.

`npx tsc --noEmit` also passes clean.

## Deploy (you run this — none of it was run here)

1. `npm i -g vercel` (or use `npx vercel` each time — already confirmed
   working: `npx --yes vercel --version` → `Vercel CLI 60.0.1`, no global
   install present).
2. `! vercel login` — interactive (opens a browser); run this yourself.
3. `cd server && vercel link` — create/link a new project, e.g.
   `cheaptripchip-api`.
4. `vercel env add GEMINI_API_KEY production` — paste your real Google AI
   Studio key (the same value currently in your local `env/dev.json`).
5. `vercel env add APP_TOKEN production` — generate one first:
   `openssl rand -hex 24`. This becomes the app's `GEMINI_API_KEY` value
   below — it is *not* the real Gemini key.
6. (Optional) `vercel env add ALLOWED_MODELS production` if you ever want to
   restrict/extend the model list beyond the three defaults.
7. `vercel --prod` — deploys `server/` with `regions: ["hnd1"]` from
   `vercel.json`.
8. Verify:
   ```
   curl https://<project>.vercel.app/api/health
   # → {"ok":true,"region":"hnd1"}

   curl -X POST "https://<project>.vercel.app/v1beta/models/gemini-3.5-flash:generateContent?key=<APP_TOKEN>" \
     -H 'Content-Type: application/json' \
     -d '{"contents":[{"parts":[{"text":"Say hi in one word."}]}],"generationConfig":{"maxOutputTokens":16}}'
   # → 200 with candidates[0].content.parts[0].text
   ```
9. Update `env/dev.json` (git-ignored, never commit it):
   ```json
   {
     "GEMINI_BASE_URL": "https://<project>.vercel.app",
     "GEMINI_API_KEY": "<the APP_TOKEN from step 5>"
   }
   ```
10. Rebuild: `flutter run --dart-define-from-file=env/dev.json` (or `flutter
    clean` first if you're rebuilding for web after touching plugins).

### Notes

- **Vercel Hobby plan supports one region per deployment.** `hnd1` (Tokyo,
  Japan) is that one region here. Japan is on Google's list of supported
  Gemini API locations, so this should clear the geo-block that hits Hong
  Kong.
- If you connect this repo to Vercel via the **Git integration** instead of
  the CLI, set the project's **Root Directory to `server`** — otherwise
  Vercel will try to build the Flutter repo root.
- `server/node_modules` and `server/.vercel` are git-ignored
  (`server/.gitignore`); nothing under `server/` has been committed by this
  task.

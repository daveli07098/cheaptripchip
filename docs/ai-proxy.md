# AI proxy (`server/`) — OpenAI chat-completions relay to OpenCode Go

## Why

The app never holds the real model key. `server/` is a small Vercel function
(pinned to Tokyo, `hnd1`) that accepts the app's OpenAI-style chat requests,
checks an app token, and relays them to OpenCode Go with the real key kept in
Vercel env. It also hosts `/api/meta` (caption fetch for the web build) and the
`/b/:id` board-invite page.

## Architecture

```
Flutter app
  → POST $AI_BASE_URL/v1/chat/completions
      Authorization: Bearer <APP_TOKEN>
      x-opencode-session: <id>
  → server/ (Vercel function, region hnd1)
      - checks APP_TOKEN, model allow-list, body size, per-IP rate limit
      - POST https://opencode.ai/inference/go/v1/chat/completions
        with the REAL key (Authorization: Bearer $OPENCODE_API_KEY)
      - returns the upstream status + JSON body unchanged
  ← OpenCode Go
```

Routing: `server/api/v1/chat/completions.ts` is the Vercel adapter, and
`server/vercel.json` rewrites the public `/v1/chat/completions` to
`/api/v1/chat/completions`; both paths reach the same handler.

### Handler logic (`server/lib/proxy.ts`)

Pure, framework-free `handleProxy(request, deps)`; vitest exercises it directly.

- **Method**: `POST` only; `OPTIONS` gets a CORS preflight reply before any
  auth check; anything else is a 404.
- **Auth**: `Authorization: Bearer <token>` must equal env `APP_TOKEN`
  (`timingSafeEqual` over SHA-256 hashes) → else 401.
- **Model allow-list**: `body.model` must be in `ALLOWED_MODELS` (env,
  comma-separated; default `glm-5.3-flash,minimax-m3.1-flash,mimo-v2.6-flash`)
  → else 404 `{error:{code,message,status}}`.
- **Body size cap**: 64 KB → 413. Requests with `image_url` content parts
  (`data:image/...;base64,...`) get 4 MB (under Vercel's ~4.5 MB limit), at
  most 4 images.
- **Response cache**: only requests with top-level `temperature === 0`, keyed
  by sha256(model + body) (not the session header), 24 h, LRU 200 entries,
  200-responses only. Hits skip the rate limiter and upstream and carry
  `X-Cache: HIT` (`MISS` otherwise). Per instance, reset on cold start.
- **Rate limit**: 30 requests / 5 min per client IP, in-memory, per instance —
  an abuse guard, not a hard quota → 429.
- **Forwarding**: `POST ${OPENCODE_BASE_URL or https://opencode.ai/inference/go}/v1/chat/completions`
  with `Authorization: Bearer $OPENCODE_API_KEY`, `User-Agent:
  cheaptripchip-api/1.0`, and `x-opencode-session`; 25 s timeout → 504, other
  network failures → 502. Missing `OPENCODE_API_KEY` → 500. Upstream non-200
  bodies pass through as-is (Go returns `{"type":"error","error":{"type","message"}}`;
  the app reads `error.message`).
- **Logging**: `[ai-proxy]` lines with model, status, latency only — never
  prompts or keys.
- **CORS**: origin echoed only for `ALLOWED_ORIGINS` (default
  `https://cheaptripchip.vercel.app`) and localhost; allowed headers
  `Authorization, x-opencode-session, Content-Type`.
- **`GET /api/health`** → `{ ok: true, region }`.

## OpenCode Go rules and models

- `x-opencode-session` is **required** by Go (400 `MissingSessionID`
  otherwise). The proxy forwards the client's value if it matches
  `^[A-Za-z0-9._-]{1,128}$`, else derives a stable one
  (`cheaptripchip-` + first 16 hex of sha256(client IP)).
- Go wants its own `User-Agent`; the proxy sends `cheaptripchip-api/1.0`.
- Go is aimed at coding-agent traffic — fine for personal/small use. If usage
  grows, move to pay-as-you-go (Zen) by setting `OPENCODE_BASE_URL`; nothing
  else changes.
- Model pool: `glm-5.3-flash`, `minimax-m3.1-flash`, `mimo-v2.6-flash`.
  DeepSeek models are served from the **Global region** only, so a
  Hong Kong/Asia origin may not reach them; they are not in the default pool.

## Environment variables (Vercel project)

| Name | Required | Purpose |
|---|---|---|
| `APP_TOKEN` | yes | Secret the app sends as the Bearer token (`openssl rand -hex 24`). |
| `OPENCODE_API_KEY` | yes | Real OpenCode Go key; never leaves the server. |
| `ALLOWED_MODELS` | no | Comma-separated override of the model allow-list. |
| `OPENCODE_BASE_URL` | no | Upstream base, default `https://opencode.ai/inference/go`. |
| `ALLOWED_ORIGINS` | no | Comma-separated browser origins allowed by CORS. |

Set the key without putting it on a command line (each command prompts for the value):

```
cd server
vercel env add OPENCODE_API_KEY production
vercel env add OPENCODE_API_KEY preview
vercel env add APP_TOKEN production      # if not already set
vercel --prod
```

## App side

`env/dev.json` (git-ignored, never commit):

```json
{
  "AI_BASE_URL": "https://cheaptripchip-api.vercel.app",
  "AI_API_KEY": "<APP_TOKEN>"
}
```

`AI_API_KEY` is the proxy's `APP_TOKEN`, not the OpenCode key.

## Smoke test

```
curl https://cheaptripchip-api.vercel.app/api/health
# → {"ok":true,"region":"hnd1"}

curl -X POST https://cheaptripchip-api.vercel.app/v1/chat/completions \
  -H "Authorization: Bearer <APP_TOKEN>" \
  -H "x-opencode-session: smoke-test" \
  -H 'Content-Type: application/json' \
  -d '{"model":"glm-5.3-flash","messages":[{"role":"user","content":"Say hi in one word."}],"max_tokens":16}'
# → 200 with choices[0].message.content

curl -s -o /dev/null -w '%{http_code}\n' -X POST https://cheaptripchip-api.vercel.app/v1/chat/completions
# → 401 (no token)
```

## Caption fetch for the web build (`server/lib/meta.ts`, `GET /api/meta`)

Native builds have `lib/services/post_metadata.dart` fetch a shared
Instagram/TikTok link directly with a crawler User-Agent, to read its
`og:title`/`og:description` as a caption for the AI (see that file's doc
comment). The web build can't do that itself — a browser can neither
cross-origin-fetch `instagram.com`/`tiktok.com` (CORS) nor send a spoofed
User-Agent — so it instead calls this proxy:

```
Flutter web (lib/services/post_metadata.dart, fetchPostMetadataViaProxy)
  → GET $AI_BASE_URL/api/meta?url=<post url>&key=<APP_TOKEN>
    (an `Authorization: Bearer <APP_TOKEN>` header is accepted too)
  → server/ (lib/meta.ts, same Vercel function family, region hnd1)
      - checks APP_TOKEN (same one as the AI proxy), CORS, per-IP rate
        limit (own "meta:" bucket — a caption-fetch burst can't starve
        AI calls or vice versa)
      - only fetches https instagram.com/www.instagram.com/tiktok.com/
        www.tiktok.com/vt.tiktok.com/vm.tiktok.com — anything else is a 400
        before any request is made
      - fetches with the crawler UA (`facebookexternalhit/1.1 ...`, same
        string `post_metadata.dart` uses natively), following up to 3
        redirects manually (each hop re-checked against the same host
        allow-list — vm./vt.tiktok.com short links redirect to the real
        video page), 8s timeout, response capped at 1.5 MB
      - parses `og:title` / `og:description` (falling back to
        `<meta name="description">`) / `og:image` the same way
        `post_metadata.dart` parses them (ported regex + HTML-entity
        unescaping, so native and web agree on the tags)
  ← { title, description, image, finalUrl } (nulls when the page has no
    usable tags, e.g. a login-wall shell)
```

`fetchPostMetadataViaProxy` maps that JSON straight into the same
`PostMetadata` type the native fetch returns, so `place_extractor.dart`
doesn't need to know which path was used. `AI_BASE_URL` and
`AI_API_KEY` (the APP_TOKEN) are the exact same `env/dev.json` values the
Gemini proxy already uses — no separate config for this endpoint.

Tests: `server/test/meta.test.ts` (host allow-list including scheme/parse
checks, auth via query/header, CORS + OPTIONS, redirect-following incl.
blocking an off-allow-list redirect and giving up after `MAX_REDIRECTS`,
body-size cap, og:tag/entity parsing, timeout → 504, network failure → 502)
and `test/post_metadata_test.dart`'s `fetchPostMetadataViaProxy` group (Dart
side, mocked `http.Client`).

**Known limitation, not fixed here**: Instagram sometimes serves its
login-wall shell (200, no usable `<meta>` tags) to datacenter IPs even with
the crawler UA — Vercel's outbound IPs may hit this depending on the post and
Instagram's mood. When that happens `/api/meta` correctly returns `200` with
all-null fields, and the web build then throws the same
`CaptionUnavailableException` a private/deleted post would. TikTok links were
not observed to have this problem in manual testing.

## Tests

```
cd server && npm install && npm test && npx tsc --noEmit
```

`test/proxy.test.ts` covers: Bearer auth, model allow-list (default + env
override), size caps and `image_url` counting, rate limiting, CORS/OPTIONS,
cache hit/miss on `temperature: 0`, session header forwarded/derived, upstream
URL/Authorization/User-Agent, missing key → 500, timeout → 504, network
failure → 502. `test/meta.test.ts` covers `/api/meta`; `test/board_page.test.ts`
covers `/b/:id`.

## Deploy notes

- First time: `vercel login`, then `cd server && vercel link` (project
  `cheaptripchip-api`), set the env vars above, `vercel --prod`.
- Vercel Hobby supports one region per deployment; `hnd1` is pinned in `vercel.json`.
- With the Git integration, set the project's **Root Directory to `server`**.
- `server/node_modules` and `server/.vercel` are git-ignored.

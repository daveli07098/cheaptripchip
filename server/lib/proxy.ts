/**
 * Pure proxy logic for the cheaptripchip AI relay (OpenCode Go).
 *
 * Kept framework-free (no @vercel/node types in here) so it's directly
 * unit-testable with vitest; `api/v1/chat/completions.ts` is the thin
 * Vercel request/response adapter that calls into `handleProxy`.
 *
 * Relays the OpenAI chat-completions shape the Flutter app sends:
 *   POST /v1/chat/completions   Authorization: Bearer <APP_TOKEN>
 *   -> 200 { choices: [...] }  or  non-200 { error: { message, ... } }
 *
 * The app's bearer token is an APP TOKEN here — the real OPENCODE_API_KEY
 * never leaves this server.
 */
import { createHash, timingSafeEqual } from 'node:crypto';

export const DEFAULT_ALLOWED_MODELS = ['glm-5.3-flash', 'minimax-m3.1-flash', 'mimo-v2.6-flash'];

export const MAX_BODY_BYTES = 64 * 1024;
/**
 * Cap for requests carrying inline images (`image_url` content parts, normally
 * `data:image/...;base64,...` URLs) — the app's "Add from screenshot" flow sends one
 * downscaled (≤1280 px) screenshot as base64. Stays under Vercel's own ~4.5 MB
 * function request-body limit, so an oversized body gets this proxy's
 * own 413 rather than a platform error page.
 */
export const MAX_IMAGE_BODY_BYTES = 4 * 1024 * 1024;
/** Max inline images per request — the app sends one; more is abuse, not a use case. */
export const MAX_INLINE_IMAGES = 4;
export const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
export const RATE_LIMIT_MAX_REQUESTS = 30;
export const UPSTREAM_TIMEOUT_MS = 25_000;

/** Response cache: identical requests within this window are served without calling the upstream. */
export const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
export const CACHE_MAX_ENTRIES = 200;

/** OpenCode Go; override with OPENCODE_BASE_URL (e.g. to move to pay-as-you-go Zen). */
export const DEFAULT_UPSTREAM_BASE = 'https://opencode.ai/inference/go';
const UPSTREAM_USER_AGENT = 'cheaptripchip-api/1.0';
/** Session ids the client may supply; anything else is replaced by a derived one. */
const SESSION_ID_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

/** Web-app origins allowed to call the proxy from a browser, unless overridden by ALLOWED_ORIGINS. */
export const DEFAULT_ALLOWED_ORIGINS = ['https://cheaptripchip.vercel.app'];

/** Local `flutter run -d chrome` / `flutter build web` + static server, any port. */
const LOCAL_DEV_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

function allowedOrigins(env: ProxyDeps['env']): string[] {
  const raw = env.ALLOWED_ORIGINS;
  if (!raw) return DEFAULT_ALLOWED_ORIGINS;
  return raw
    .split(',')
    .map((o) => o.trim().replace(/\/+$/, ''))
    .filter(Boolean);
}

/**
 * CORS headers for this request. The Origin is echoed only when it's the web
 * app (or local dev); other sites get no Access-Control-Allow-Origin, so
 * browsers refuse to hand them the response. Native apps send no Origin and
 * are unaffected — CORS is a browser rule, the APP_TOKEN check is the real gate.
 */
export function corsHeaders(
  headers: Record<string, string | string[] | undefined>,
  env: ProxyDeps['env'],
  methods = 'POST, OPTIONS',
): Record<string, string> {
  const cors: Record<string, string> = {
    'Access-Control-Allow-Methods': methods,
    'Access-Control-Allow-Headers': 'Authorization, x-opencode-session, Content-Type, x-goog-api-key',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  const origin = headerValue(headers, 'origin');
  if (origin && (LOCAL_DEV_ORIGIN.test(origin) || allowedOrigins(env).includes(origin))) {
    cors['Access-Control-Allow-Origin'] = origin;
  }
  return cors;
}

/** An error body shaped like the upstream's (`error.message`), so the app's error parsing keeps working. */
function apiError(code: number, message: string, status: string) {
  return { error: { code, message, status } };
}

export interface ProxyRequest {
  method: string;
  query: Record<string, string | string[] | undefined>;
  headers: Record<string, string | string[] | undefined>;
  /** Already JSON-parsed body (Vercel's Node runtime parses it for us), or undefined. */
  body: unknown;
  /** From the Content-Length header, when present — used for the size cap. */
  contentLength: number | undefined;
  ip: string;
}

export interface ProxyResponse {
  status: number;
  headers: Record<string, string>;
  body: unknown;
}

export interface ProxyDeps {
  fetch: typeof fetch;
  now: () => number;
  env: NodeJS.ProcessEnv | Record<string, string | undefined>;
}

// Per-instance, in-memory rate limiter — resets on cold start and is NOT shared
// across concurrent Vercel instances. Best-effort abuse guard only, not a hard cap.
interface RateWindow {
  count: number;
  windowStart: number;
}
const rateLimitStore = new Map<string, RateWindow>();

/** Test-only: clear rate-limit state between test cases. */
export function resetRateLimiter(): void {
  rateLimitStore.clear();
}

/** Exported so `lib/meta.ts` shares the same in-memory limiter/store shape (with its own key prefix, so the two endpoints don't share a bucket). */
export function checkRateLimit(ip: string, now: number): boolean {
  const entry = rateLimitStore.get(ip);
  if (!entry || now - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateLimitStore.set(ip, { count: 1, windowStart: now });
    return true;
  }
  entry.count += 1;
  return entry.count <= RATE_LIMIT_MAX_REQUESTS;
}

/** Constant-time string compare (hash first so unequal lengths don't short-circuit). */
export function safeEqual(a: string, b: string): boolean {
  const ah = createHash('sha256').update(a).digest();
  const bh = createHash('sha256').update(b).digest();
  return timingSafeEqual(ah, bh);
}

export function headerValue(
  headers: Record<string, string | string[] | undefined>,
  name: string,
): string | undefined {
  const v = headers[name] ?? headers[name.toLowerCase()];
  return Array.isArray(v) ? v[0] : v;
}

export function queryValue(
  query: Record<string, string | string[] | undefined>,
  name: string,
): string | undefined {
  const v = query[name];
  return Array.isArray(v) ? v[0] : v;
}

function allowedModels(env: ProxyDeps['env']): string[] {
  const raw = env.ALLOWED_MODELS;
  if (!raw) return DEFAULT_ALLOWED_MODELS;
  return raw
    .split(',')
    .map((m) => m.trim())
    .filter(Boolean);
}

/**
 * Number of `image_url` content parts across `messages[].content[]` of an
 * OpenAI chat body. Text-only messages (string content or `text` parts) don't
 * count, so they stay under the small text cap.
 */
export function countInlineImages(body: unknown): number {
  if (!body || typeof body !== 'object') return 0;
  const messages = (body as { messages?: unknown }).messages;
  if (!Array.isArray(messages)) return 0;
  let count = 0;
  for (const message of messages) {
    const content = (message as { content?: unknown } | null)?.content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      if (part && typeof part === 'object' && (part as { type?: unknown }).type === 'image_url') {
        count += 1;
      }
    }
  }
  return count;
}

/** Body cap for this request: the image cap when it carries inline images, else the text cap. */
export function bodyCap(body: unknown): number {
  return countInlineImages(body) > 0 ? MAX_IMAGE_BODY_BYTES : MAX_BODY_BYTES;
}

// Per-instance, in-memory LRU response cache (Map keeps insertion order; a hit
// is re-inserted to mark it most-recent). Like the rate limiter it resets on
// cold start and isn't shared across instances — a cost/latency saver for
// repeat extractions of the same post, not a guarantee.
interface CacheEntry {
  status: number;
  body: unknown;
  storedAt: number;
}
const responseCache = new Map<string, CacheEntry>();

/** Test-only: clear the response cache between test cases. */
export function resetResponseCache(): void {
  responseCache.clear();
}

/**
 * Only deterministic requests are cached: top-level `temperature === 0`
 * (what the app's JSON-extraction calls send). A sampled request (default or
 * non-zero temperature) is expected to vary, so replaying one would change its
 * meaning.
 */
export function isCacheable(body: unknown): boolean {
  if (!body || typeof body !== 'object') return false;
  return (body as { temperature?: unknown }).temperature === 0;
}

export function cacheKey(model: string, body: unknown): string {
  return createHash('sha256')
    .update(model)
    .update('\n')
    .update(JSON.stringify(body ?? {}))
    .digest('hex');
}

function cacheGet(key: string, now: number): CacheEntry | undefined {
  const entry = responseCache.get(key);
  if (!entry) return undefined;
  responseCache.delete(key);
  if (now - entry.storedAt >= CACHE_TTL_MS) return undefined;
  responseCache.set(key, entry); // bump to most-recent
  return entry;
}

function cacheSet(key: string, entry: CacheEntry): void {
  responseCache.delete(key);
  responseCache.set(key, entry);
  while (responseCache.size > CACHE_MAX_ENTRIES) {
    const oldest = responseCache.keys().next().value;
    if (oldest === undefined) break;
    responseCache.delete(oldest);
  }
}

function bodySize(req: ProxyRequest): number {
  if (typeof req.contentLength === 'number' && !Number.isNaN(req.contentLength)) {
    return req.contentLength;
  }
  try {
    return Buffer.byteLength(JSON.stringify(req.body ?? {}), 'utf8');
  } catch {
    return 0;
  }
}

/** Bearer token from the Authorization header, if any. */
function bearerToken(headers: ProxyRequest['headers']): string | undefined {
  const raw = headerValue(headers, 'authorization');
  const m = raw ? /^Bearer\s+(.+)$/i.exec(raw.trim()) : null;
  return m?.[1];
}

/**
 * OpenCode Go requires an `x-opencode-session` header (400 MissingSessionID
 * otherwise). Forward the client's when well-formed, else derive a stable one
 * from the client IP.
 */
function sessionId(req: ProxyRequest): string {
  const supplied = headerValue(req.headers, 'x-opencode-session');
  if (supplied && SESSION_ID_PATTERN.test(supplied)) return supplied;
  return `cheaptripchip-${createHash('sha256').update(req.ip).digest('hex').slice(0, 16)}`;
}

export async function handleProxy(req: ProxyRequest, deps: ProxyDeps): Promise<ProxyResponse> {
  const started = deps.now();
  const cors = corsHeaders(req.headers, deps.env);

  if (req.method === 'OPTIONS') {
    return { status: 204, headers: { ...cors }, body: undefined };
  }

  if (req.method !== 'POST') {
    return {
      status: 404,
      headers: { ...cors },
      body: apiError(404, 'Not found.', 'NOT_FOUND'),
    };
  }

  const appToken = bearerToken(req.headers);
  const expectedToken = deps.env.APP_TOKEN;
  if (!expectedToken || !appToken || !safeEqual(appToken, expectedToken)) {
    return {
      status: 401,
      headers: { ...cors },
      body: apiError(401, 'Invalid app token', 'UNAUTHENTICATED'),
    };
  }

  const model = (req.body as { model?: unknown } | null | undefined)?.model;
  if (typeof model !== 'string' || !allowedModels(deps.env).includes(model)) {
    return {
      status: 404,
      headers: { ...cors },
      body: apiError(
        404,
        `model ${typeof model === 'string' ? model : ''} is not found or not allowed by this proxy`,
        'NOT_FOUND',
      ),
    };
  }

  if (bodySize(req) > bodyCap(req.body) || countInlineImages(req.body) > MAX_INLINE_IMAGES) {
    return {
      status: 413,
      headers: { ...cors },
      body: apiError(413, 'Request body too large', 'INVALID_ARGUMENT'),
    };
  }

  // Cache hits are served before the rate limiter: they cost nothing upstream.
  const cacheable = isCacheable(req.body);
  const key = cacheable ? cacheKey(model, req.body) : undefined;
  if (key) {
    const hit = cacheGet(key, deps.now());
    if (hit) {
      console.log(`[ai-proxy] model=${model} status=${hit.status} cache=hit`);
      return { status: hit.status, headers: { ...cors, 'X-Cache': 'HIT' }, body: hit.body };
    }
  }

  if (!checkRateLimit(req.ip, deps.now())) {
    return {
      status: 429,
      headers: { ...cors },
      body: apiError(
        429,
        'Rate limit exceeded, please try again later.',
        'RESOURCE_EXHAUSTED',
      ),
    };
  }

  const apiKey = deps.env.OPENCODE_API_KEY;
  if (!apiKey) {
    return {
      status: 500,
      headers: { ...cors },
      body: apiError(500, 'Proxy is missing OPENCODE_API_KEY', 'INTERNAL'),
    };
  }

  const base = (deps.env.OPENCODE_BASE_URL || DEFAULT_UPSTREAM_BASE).replace(/\/+$/, '');
  const upstreamUrl = `${base}/v1/chat/completions`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  try {
    const upstream = await deps.fetch(upstreamUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
        'User-Agent': UPSTREAM_USER_AGENT,
        'x-opencode-session': sessionId(req),
      },
      body: JSON.stringify(req.body ?? {}),
      signal: controller.signal,
    });

    const text = await upstream.text();
    let body: unknown;
    try {
      body = text.length > 0 ? JSON.parse(text) : {};
    } catch {
      body = { error: { code: upstream.status, message: text, status: 'UNKNOWN' } };
    }

    // Never log prompts or keys — only model, status, latency.
    console.log(
      `[ai-proxy] model=${model} status=${upstream.status} latencyMs=${deps.now() - started}`,
    );

    if (key && upstream.status === 200) {
      cacheSet(key, { status: upstream.status, body, storedAt: deps.now() });
    }
    return {
      status: upstream.status,
      headers: key ? { ...cors, 'X-Cache': 'MISS' } : { ...cors },
      body,
    };
  } catch (e) {
    const isAbort = e instanceof Error && e.name === 'AbortError';
    console.log(
      `[ai-proxy] model=${model} status=${isAbort ? 504 : 502} latencyMs=${deps.now() - started} error=${isAbort ? 'timeout' : 'fetch-failed'}`,
    );
    if (isAbort) {
      return {
        status: 504,
        headers: { ...cors },
        body: apiError(504, 'Upstream AI request timed out', 'DEADLINE_EXCEEDED'),
      };
    }
    return {
      status: 502,
      headers: { ...cors },
      body: apiError(502, 'Failed to reach upstream AI API', 'UNAVAILABLE'),
    };
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Pure proxy logic for the cheaptripchip Gemini relay.
 *
 * Kept framework-free (no @vercel/node types in here) so it's directly
 * unit-testable with vitest; `api/v1beta/models/[modelAction].ts` is the thin
 * Vercel request/response adapter that calls into `handleProxy`.
 *
 * Mirrors the shape the Flutter app (`lib/services/gemini_service.dart`)
 * expects from the real Gemini Developer API:
 *   POST /v1beta/models/<model>:generateContent?key=<token>
 *   -> 200 { candidates: [...] }  or  non-200 { error: { message, ... } }
 *
 * The app's `key` query param becomes an APP TOKEN here — the real
 * GEMINI_API_KEY never leaves this server.
 */
import { createHash, timingSafeEqual } from 'node:crypto';

export const DEFAULT_ALLOWED_MODELS = [
  'gemini-3.8-flash',
  'gemini-3.5-flash',
  'gemini-3.1-flash-lite',
];

export const MAX_BODY_BYTES = 64 * 1024;
/**
 * Cap for requests carrying inline images (`inline_data` / `inlineData` parts
 * with an `image/*` mime type) — the app's "Add from screenshot" flow sends one
 * downscaled (≤1280 px) screenshot as base64. Stays under Vercel's own ~4.5 MB
 * function request-body limit, so an oversized body gets this proxy's
 * Gemini-shaped 413 rather than a platform error page.
 */
export const MAX_IMAGE_BODY_BYTES = 4 * 1024 * 1024;
/** Max inline images per request — the app sends one; more is abuse, not a use case. */
export const MAX_INLINE_IMAGES = 4;
export const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
export const RATE_LIMIT_MAX_REQUESTS = 30;
export const UPSTREAM_TIMEOUT_MS = 25_000;

/** Response cache: identical requests within this window are served without calling Gemini. */
export const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
export const CACHE_MAX_ENTRIES = 200;

const UPSTREAM_BASE = 'https://generativelanguage.googleapis.com';

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
    'Access-Control-Allow-Headers': 'Content-Type, x-goog-api-key',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
  const origin = headerValue(headers, 'origin');
  if (origin && (LOCAL_DEV_ORIGIN.test(origin) || allowedOrigins(env).includes(origin))) {
    cors['Access-Control-Allow-Origin'] = origin;
  }
  return cors;
}

/** A Gemini-shaped error body, so the app's cascade / error parsing keeps working. */
function geminiError(code: number, message: string, status: string) {
  return { error: { code, message, status } };
}

export interface ProxyRequest {
  method: string;
  /** The dynamic path segment, e.g. "gemini-3.5-flash:generateContent". */
  modelAction: string | undefined;
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

/** Splits "gemini-3.5-flash:generateContent" into { model, action }. */
export function parseModelAction(
  modelAction: string | undefined,
): { model: string; action: string } | null {
  if (!modelAction) return null;
  // Defensive: if the rewrite (or a proxy in front of Vercel) ever percent-encodes
  // the colon (":" -> "%3A"), decode before splitting so routing still resolves.
  let decoded = modelAction;
  try {
    decoded = decodeURIComponent(modelAction);
  } catch {
    /* not percent-encoded — use as-is */
  }
  const colonIndex = decoded.indexOf(':');
  if (colonIndex === -1) return null;
  const model = decoded.slice(0, colonIndex);
  const action = decoded.slice(colonIndex + 1);
  if (!model || !action) return null;
  return { model, action };
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
 * Number of inline image parts in a generateContent body (both the REST
 * snake_case `inline_data`/`mime_type` and the camelCase `inlineData`/
 * `mimeType` spellings Gemini accepts). Non-image inline data (audio, PDF…)
 * doesn't count, so it stays under the small text cap.
 */
export function countInlineImages(body: unknown): number {
  if (!body || typeof body !== 'object') return 0;
  const contents = (body as { contents?: unknown }).contents;
  if (!Array.isArray(contents)) return 0;
  let count = 0;
  for (const content of contents) {
    const parts = (content as { parts?: unknown } | null)?.parts;
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (!part || typeof part !== 'object') continue;
      const inline =
        (part as Record<string, unknown>).inline_data ?? (part as Record<string, unknown>).inlineData;
      if (!inline || typeof inline !== 'object') continue;
      const mime =
        (inline as Record<string, unknown>).mime_type ?? (inline as Record<string, unknown>).mimeType;
      if (typeof mime === 'string' && mime.toLowerCase().startsWith('image/')) count += 1;
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
 * Only deterministic requests are cached: `generationConfig.temperature === 0`
 * (what the app's JSON-extraction calls send). A sampled request (default or
 * non-zero temperature) is expected to vary, so replaying one would change its
 * meaning.
 */
export function isCacheable(body: unknown): boolean {
  if (!body || typeof body !== 'object') return false;
  const config = (body as { generationConfig?: unknown }).generationConfig;
  if (!config || typeof config !== 'object') return false;
  return (config as { temperature?: unknown }).temperature === 0;
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
      body: geminiError(404, 'Not found.', 'NOT_FOUND'),
    };
  }

  const parsed = parseModelAction(req.modelAction);
  if (!parsed || parsed.action !== 'generateContent' || !allowedModels(deps.env).includes(parsed.model)) {
    return {
      status: 404,
      headers: { ...cors },
      body: geminiError(
        404,
        `models/${req.modelAction ?? ''} is not found or not allowed by this proxy`,
        'NOT_FOUND',
      ),
    };
  }

  const appToken = queryValue(req.query, 'key') ?? headerValue(req.headers, 'x-goog-api-key');
  const expectedToken = deps.env.APP_TOKEN;
  if (!expectedToken || !appToken || !safeEqual(appToken, expectedToken)) {
    return {
      status: 401,
      headers: { ...cors },
      body: geminiError(401, 'Invalid app token', 'UNAUTHENTICATED'),
    };
  }

  if (bodySize(req) > bodyCap(req.body) || countInlineImages(req.body) > MAX_INLINE_IMAGES) {
    return {
      status: 413,
      headers: { ...cors },
      body: geminiError(413, 'Request body too large', 'INVALID_ARGUMENT'),
    };
  }

  // Cache hits are served before the rate limiter: they cost nothing upstream.
  const cacheable = isCacheable(req.body);
  const key = cacheable ? cacheKey(parsed.model, req.body) : undefined;
  if (key) {
    const hit = cacheGet(key, deps.now());
    if (hit) {
      console.log(`[gemini-proxy] model=${parsed.model} status=${hit.status} cache=hit`);
      return { status: hit.status, headers: { ...cors, 'X-Cache': 'HIT' }, body: hit.body };
    }
  }

  if (!checkRateLimit(req.ip, deps.now())) {
    return {
      status: 429,
      headers: { ...cors },
      body: geminiError(
        429,
        'Rate limit exceeded, please try again later.',
        'RESOURCE_EXHAUSTED',
      ),
    };
  }

  const geminiApiKey = deps.env.GEMINI_API_KEY;
  if (!geminiApiKey) {
    return {
      status: 500,
      headers: { ...cors },
      body: geminiError(500, 'Proxy is missing GEMINI_API_KEY', 'INTERNAL'),
    };
  }

  const upstreamUrl = `${UPSTREAM_BASE}/v1beta/models/${parsed.model}:generateContent`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);

  try {
    const upstream = await deps.fetch(upstreamUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': geminiApiKey,
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
      `[gemini-proxy] model=${parsed.model} status=${upstream.status} latencyMs=${deps.now() - started}`,
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
      `[gemini-proxy] model=${parsed.model} status=${isAbort ? 504 : 502} latencyMs=${deps.now() - started} error=${isAbort ? 'timeout' : 'fetch-failed'}`,
    );
    if (isAbort) {
      return {
        status: 504,
        headers: { ...cors },
        body: geminiError(504, 'Upstream Gemini request timed out', 'DEADLINE_EXCEEDED'),
      };
    }
    return {
      status: 502,
      headers: { ...cors },
      body: geminiError(502, 'Failed to reach upstream Gemini API', 'UNAVAILABLE'),
    };
  } finally {
    clearTimeout(timeout);
  }
}

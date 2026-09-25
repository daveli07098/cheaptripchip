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
export const RATE_LIMIT_WINDOW_MS = 5 * 60 * 1000;
export const RATE_LIMIT_MAX_REQUESTS = 30;
export const UPSTREAM_TIMEOUT_MS = 25_000;

const UPSTREAM_BASE = 'https://generativelanguage.googleapis.com';

const CORS_HEADERS: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, x-goog-api-key',
};

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

function checkRateLimit(ip: string, now: number): boolean {
  const entry = rateLimitStore.get(ip);
  if (!entry || now - entry.windowStart >= RATE_LIMIT_WINDOW_MS) {
    rateLimitStore.set(ip, { count: 1, windowStart: now });
    return true;
  }
  entry.count += 1;
  return entry.count <= RATE_LIMIT_MAX_REQUESTS;
}

/** Constant-time string compare (hash first so unequal lengths don't short-circuit). */
function safeEqual(a: string, b: string): boolean {
  const ah = createHash('sha256').update(a).digest();
  const bh = createHash('sha256').update(b).digest();
  return timingSafeEqual(ah, bh);
}

function headerValue(
  headers: Record<string, string | string[] | undefined>,
  name: string,
): string | undefined {
  const v = headers[name] ?? headers[name.toLowerCase()];
  return Array.isArray(v) ? v[0] : v;
}

function queryValue(
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

  if (req.method === 'OPTIONS') {
    return { status: 204, headers: { ...CORS_HEADERS }, body: undefined };
  }

  if (req.method !== 'POST') {
    return {
      status: 404,
      headers: { ...CORS_HEADERS },
      body: geminiError(404, 'Not found.', 'NOT_FOUND'),
    };
  }

  const parsed = parseModelAction(req.modelAction);
  if (!parsed || parsed.action !== 'generateContent' || !allowedModels(deps.env).includes(parsed.model)) {
    return {
      status: 404,
      headers: { ...CORS_HEADERS },
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
      headers: { ...CORS_HEADERS },
      body: geminiError(401, 'Invalid app token', 'UNAUTHENTICATED'),
    };
  }

  if (bodySize(req) > MAX_BODY_BYTES) {
    return {
      status: 413,
      headers: { ...CORS_HEADERS },
      body: geminiError(413, 'Request body too large', 'INVALID_ARGUMENT'),
    };
  }

  if (!checkRateLimit(req.ip, deps.now())) {
    return {
      status: 429,
      headers: { ...CORS_HEADERS },
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
      headers: { ...CORS_HEADERS },
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

    return { status: upstream.status, headers: { ...CORS_HEADERS }, body };
  } catch (e) {
    const isAbort = e instanceof Error && e.name === 'AbortError';
    console.log(
      `[gemini-proxy] model=${parsed.model} status=${isAbort ? 504 : 502} latencyMs=${deps.now() - started} error=${isAbort ? 'timeout' : 'fetch-failed'}`,
    );
    if (isAbort) {
      return {
        status: 504,
        headers: { ...CORS_HEADERS },
        body: geminiError(504, 'Upstream Gemini request timed out', 'DEADLINE_EXCEEDED'),
      };
    }
    return {
      status: 502,
      headers: { ...CORS_HEADERS },
      body: geminiError(502, 'Failed to reach upstream Gemini API', 'UNAVAILABLE'),
    };
  } finally {
    clearTimeout(timeout);
  }
}

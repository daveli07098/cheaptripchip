/**
 * Pure logic for `GET /api/meta?url=<encoded post url>` — the web-build
 * counterpart to `lib/services/post_metadata.dart`'s native fetch.
 *
 * Browsers can't read an Instagram/TikTok post's og:meta tags directly: a
 * `fetch('https://instagram.com/...')` from a web page is blocked by CORS,
 * and browsers won't let a page send a spoofed `User-Agent` even if CORS
 * weren't an issue. This endpoint does the crawler-UA fetch server-side
 * (same UA `post_metadata.dart` uses, verified against public IG/TikTok
 * posts) and hands back just the parsed tags, so the Flutter web build gets
 * the same caption data the native build reads for itself.
 *
 * Framework-free like `lib/proxy.ts`, for the same reason: directly
 * unit-testable with vitest, with `api/meta.ts` as the thin Vercel adapter.
 * Shares that file's auth (APP_TOKEN), CORS allow-list, and per-IP rate
 * limiter (own key prefix, so a burst of AI calls can't starve caption
 * fetches or vice versa).
 */
import {
  checkRateLimit,
  corsHeaders,
  headerValue,
  queryValue,
  safeEqual,
  type ProxyDeps,
} from './proxy.js';

/** Crawler UA Instagram/TikTok serve public og:meta tags to — must match `post_metadata.dart`'s `_crawlerUserAgent` exactly. */
const CRAWLER_USER_AGENT =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

/** Exact hosts this endpoint will ever fetch — both the initial URL and every redirect hop must match one of these. */
const ALLOWED_HOSTS = new Set([
  'instagram.com',
  'www.instagram.com',
  'tiktok.com',
  'www.tiktok.com',
  'vt.tiktok.com',
  'vm.tiktok.com',
]);

export const MAX_REDIRECTS = 3;
export const FETCH_TIMEOUT_MS = 8_000;
export const MAX_RESPONSE_BYTES = 1.5 * 1024 * 1024;

function isAllowedUrl(url: URL): boolean {
  return url.protocol === 'https:' && ALLOWED_HOSTS.has(url.hostname.toLowerCase());
}

export interface MetaRequest {
  method: string;
  query: Record<string, string | string[] | undefined>;
  headers: Record<string, string | string[] | undefined>;
  ip: string;
}

export interface MetaResponse {
  status: number;
  headers: Record<string, string>;
  body: unknown;
}

export type MetaDeps = ProxyDeps;

function errorBody(message: string) {
  return { error: message };
}

// --- og:meta parsing, ported line-for-line from post_metadata.dart's
// _parseMetaTags/_unescapeHtml so the web and native paths agree on tags. ---

const META_TAG_PATTERN = /<meta\b[^>]*>/gi;
// 's' flag == Dart's dotAll: a caption in `content="..."` can contain literal
// newlines (multi-line IG captions render that way in the raw HTML).
const META_KEY_PATTERN = /(?:property|name)\s*=\s*(["'])(.*?)\1/is;
const META_CONTENT_PATTERN = /content\s*=\s*(["'])(.*?)\1/is;

const WANTED_META_KEYS = new Set(['og:title', 'og:description', 'og:image', 'description']);

function parseMetaTags(html: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const tagMatch of html.matchAll(META_TAG_PATTERN)) {
    const tag = tagMatch[0];
    const key = META_KEY_PATTERN.exec(tag)?.[2]?.toLowerCase();
    const content = META_CONTENT_PATTERN.exec(tag)?.[2];
    if (!key || content === undefined || !WANTED_META_KEYS.has(key)) continue;
    if (!(key in result)) result[key] = unescapeHtml(content); // first occurrence wins
  }
  return result;
}

const ENTITY_PATTERN = /&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g;
const NAMED_ENTITIES: Record<string, string> = {
  amp: '&',
  quot: '"',
  apos: "'",
  lt: '<',
  gt: '>',
  nbsp: ' ',
};

/** HTML-unescapes `s` in a single pass — named entities, decimal (`&#64;`) and hex (`&#x2019;`) numeric refs. */
function unescapeHtml(s: string): string {
  return s.replace(ENTITY_PATTERN, (match, body: string) => {
    if (body[0] === '#' && (body[1] === 'x' || body[1] === 'X')) {
      const code = parseInt(body.slice(2), 16);
      return Number.isNaN(code) ? match : String.fromCodePoint(code);
    }
    if (body[0] === '#') {
      const code = parseInt(body.slice(1), 10);
      return Number.isNaN(code) ? match : String.fromCodePoint(code);
    }
    return NAMED_ENTITIES[body.toLowerCase()] ?? match;
  });
}

/** Reads `body` up to `maxBytes`, then cancels the stream — protects against a huge/streaming response. */
async function readCapped(body: ReadableStream<Uint8Array> | null, maxBytes: number): Promise<string> {
  if (!body) return '';
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8');
  let out = '';
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      const allowed = Math.max(0, value.byteLength - (total - maxBytes));
      out += decoder.decode(value.subarray(0, allowed));
      await reader.cancel();
      break;
    }
    out += decoder.decode(value, { stream: true });
  }
  return out;
}

type FetchResult =
  | { ok: true; res: Response; finalUrl: string }
  | { ok: false; reason: 'bad_host' | 'too_many_redirects' | 'network' };

/** Fetches `start`, following up to [MAX_REDIRECTS] redirects manually — every hop (including `start`) must resolve to an [ALLOWED_HOSTS] https URL. */
async function fetchFollowingRedirects(
  start: URL,
  deps: MetaDeps,
  signal: AbortSignal,
): Promise<FetchResult> {
  let current = start;
  for (let hop = 0; ; hop++) {
    if (!isAllowedUrl(current)) return { ok: false, reason: 'bad_host' };
    let res: Response;
    try {
      res = await deps.fetch(current.toString(), {
        redirect: 'manual',
        headers: { 'User-Agent': CRAWLER_USER_AGENT },
        signal,
      });
    } catch (e) {
      // Let an abort (timeout) propagate to the outer catch, which maps it to
      // 504 specifically — everything else here is a generic 502.
      if (e instanceof Error && e.name === 'AbortError') throw e;
      return { ok: false, reason: 'network' };
    }
    if (res.status >= 300 && res.status < 400) {
      const location = res.headers.get('location');
      if (!location) return { ok: false, reason: 'network' };
      if (hop >= MAX_REDIRECTS) return { ok: false, reason: 'too_many_redirects' };
      current = new URL(location, current);
      continue;
    }
    return { ok: true, res, finalUrl: current.toString() };
  }
}

export async function handleMeta(req: MetaRequest, deps: MetaDeps): Promise<MetaResponse> {
  const cors = corsHeaders(req.headers, deps.env, 'GET, OPTIONS');

  if (req.method === 'OPTIONS') {
    return { status: 204, headers: { ...cors }, body: undefined };
  }
  if (req.method !== 'GET') {
    return {
      status: 405,
      headers: { ...cors, Allow: 'GET, OPTIONS' },
      body: errorBody('Method not allowed'),
    };
  }

  const bearer = /^Bearer\s+(.+)$/i.exec((headerValue(req.headers, 'authorization') ?? '').trim())?.[1];
  const appToken =
    queryValue(req.query, 'key') ?? headerValue(req.headers, 'x-goog-api-key') ?? bearer;
  const expectedToken = deps.env.APP_TOKEN;
  if (!expectedToken || !appToken || !safeEqual(appToken, expectedToken)) {
    return { status: 401, headers: { ...cors }, body: errorBody('Invalid app token') };
  }

  if (!checkRateLimit(`meta:${req.ip}`, deps.now())) {
    return {
      status: 429,
      headers: { ...cors },
      body: errorBody('Rate limit exceeded, please try again later.'),
    };
  }

  const rawUrl = queryValue(req.query, 'url');
  if (!rawUrl) {
    return { status: 400, headers: { ...cors }, body: errorBody('Missing url parameter') };
  }
  let target: URL;
  try {
    target = new URL(rawUrl);
  } catch {
    return { status: 400, headers: { ...cors }, body: errorBody('Invalid url parameter') };
  }
  if (!isAllowedUrl(target)) {
    return { status: 400, headers: { ...cors }, body: errorBody('Host not allowed') };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const result = await fetchFollowingRedirects(target, deps, controller.signal);
    if (!result.ok) {
      if (result.reason === 'bad_host') {
        return { status: 400, headers: { ...cors }, body: errorBody('Redirected to a disallowed host') };
      }
      return { status: 502, headers: { ...cors }, body: errorBody('Failed to fetch post') };
    }
    if (!result.res.ok) {
      return {
        status: 502,
        headers: { ...cors },
        body: errorBody(`Upstream returned ${result.res.status}`),
      };
    }
    const html = await readCapped(result.res.body, MAX_RESPONSE_BYTES);
    const tags = parseMetaTags(html);
    return {
      status: 200,
      headers: { ...cors },
      body: {
        title: tags['og:title'] ?? null,
        description: tags['og:description'] ?? tags['description'] ?? null,
        image: tags['og:image'] ?? null,
        finalUrl: result.finalUrl,
      },
    };
  } catch (e) {
    const isAbort = e instanceof Error && e.name === 'AbortError';
    return {
      status: isAbort ? 504 : 502,
      headers: { ...cors },
      body: errorBody(isAbort ? 'Upstream request timed out' : 'Failed to fetch post'),
    };
  } finally {
    clearTimeout(timeout);
  }
}

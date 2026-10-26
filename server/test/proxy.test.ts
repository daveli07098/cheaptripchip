import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  DEFAULT_ALLOWED_MODELS,
  CACHE_MAX_ENTRIES,
  CACHE_TTL_MS,
  MAX_BODY_BYTES,
  MAX_IMAGE_BODY_BYTES,
  MAX_INLINE_IMAGES,
  countInlineImages,
  RATE_LIMIT_MAX_REQUESTS,
  handleProxy,
  DEFAULT_UPSTREAM_BASE,
  resetRateLimiter,
  resetResponseCache,
  type ProxyDeps,
  type ProxyRequest,
} from '../lib/proxy.js';

const BASE_ENV = {
  APP_TOKEN: 'test-app-token',
  OPENCODE_API_KEY: 'real-opencode-key',
};

function chatBody(extra: Record<string, unknown> = {}) {
  return {
    model: 'glm-5.3-flash',
    messages: [{ role: 'user', content: 'hi' }],
    ...extra,
  };
}

function makeReq(overrides: Partial<ProxyRequest> = {}): ProxyRequest {
  return {
    method: 'POST',
    query: {},
    headers: { authorization: `Bearer ${BASE_ENV.APP_TOKEN}` },
    body: chatBody(),
    contentLength: undefined,
    ip: '1.2.3.4',
    ...overrides,
  };
}

function makeDeps(overrides: Partial<ProxyDeps> = {}): ProxyDeps {
  // A fresh Response per call — Response bodies are single-read streams, and
  // several tests call handleProxy repeatedly against the same deps object.
  const defaultFetch = vi.fn().mockImplementation(
    async () =>
      new Response(
        JSON.stringify({ choices: [{ message: { role: 'assistant', content: 'ok' } }] }),
        { status: 200 },
      ),
  );
  return {
    fetch: defaultFetch,
    now: () => 1_000_000,
    env: { ...BASE_ENV },
    ...overrides,
  };
}

beforeEach(() => {
  resetRateLimiter();
  resetResponseCache();
  vi.restoreAllMocks();
});

describe('handleProxy — model allow-list', () => {
  it('allows every default model', async () => {
    for (const model of DEFAULT_ALLOWED_MODELS) {
      const res = await handleProxy(makeReq({ body: chatBody({ model }) }), makeDeps());
      expect(res.status).toBe(200);
    }
  });

  it('rejects a model not on the list with a 404 error body', async () => {
    const deps = makeDeps();
    const res = await handleProxy(makeReq({ body: chatBody({ model: 'gpt-9000' }) }), deps);
    expect(res.status).toBe(404);
    expect(res.body).toMatchObject({ error: { code: 404, status: 'NOT_FOUND' } });
    expect(deps.fetch).not.toHaveBeenCalled();
  });

  it('rejects a missing model or missing body', async () => {
    expect((await handleProxy(makeReq({ body: { messages: [] } }), makeDeps())).status).toBe(404);
    expect((await handleProxy(makeReq({ body: undefined }), makeDeps())).status).toBe(404);
  });

  it('honors a custom ALLOWED_MODELS env override', async () => {
    const res = await handleProxy(
      makeReq({ body: chatBody({ model: 'custom-model' }) }),
      makeDeps({ env: { ...BASE_ENV, ALLOWED_MODELS: 'custom-model' } }),
    );
    expect(res.status).toBe(200);
  });
});

describe('handleProxy — auth', () => {
  it('rejects a missing token with 401', async () => {
    const res = await handleProxy(makeReq({ headers: {} }), makeDeps());
    expect(res.status).toBe(401);
    expect(res.body).toMatchObject({ error: { code: 401 } });
  });

  it('rejects a wrong token with 401', async () => {
    const res = await handleProxy(makeReq({ headers: { authorization: 'Bearer wrong' } }), makeDeps());
    expect(res.status).toBe(401);
  });

  it('rejects a non-Bearer Authorization header and the old query key', async () => {
    const basic = await handleProxy(
      makeReq({ headers: { authorization: BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(basic.status).toBe(401);
    const query = await handleProxy(
      makeReq({ headers: {}, query: { key: BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(query.status).toBe(401);
  });

  it('rejects everything when APP_TOKEN is unset', async () => {
    const res = await handleProxy(makeReq(), makeDeps({ env: { OPENCODE_API_KEY: 'k' } }));
    expect(res.status).toBe(401);
  });
});

describe('handleProxy — body size cap', () => {
  it('rejects an oversized body via content-length', async () => {
    const res = await handleProxy(makeReq({ contentLength: MAX_BODY_BYTES + 1 }), makeDeps());
    expect(res.status).toBe(413);
  });

  it('allows a body at the cap', async () => {
    const res = await handleProxy(makeReq({ contentLength: MAX_BODY_BYTES }), makeDeps());
    expect(res.status).toBe(200);
  });
});

describe('handleProxy — rate limiting', () => {
  it('allows up to RATE_LIMIT_MAX_REQUESTS then 429s', async () => {
    const deps = makeDeps();
    let last;
    for (let i = 0; i < RATE_LIMIT_MAX_REQUESTS; i++) {
      last = await handleProxy(makeReq(), deps);
      expect(last.status).toBe(200);
    }
    const blocked = await handleProxy(makeReq(), deps);
    expect(blocked.status).toBe(429);
    expect(blocked.body).toMatchObject({ error: { code: 429, status: 'RESOURCE_EXHAUSTED' } });
  });

  it('tracks limits per IP independently', async () => {
    const deps = makeDeps();
    for (let i = 0; i < RATE_LIMIT_MAX_REQUESTS; i++) {
      await handleProxy(makeReq({ ip: 'ip-a' }), deps);
    }
    const blockedA = await handleProxy(makeReq({ ip: 'ip-a' }), deps);
    const okB = await handleProxy(makeReq({ ip: 'ip-b' }), deps);
    expect(blockedA.status).toBe(429);
    expect(okB.status).toBe(200);
  });

  it('resets the window after RATE_LIMIT_WINDOW_MS elapses', async () => {
    let now = 0;
    const deps = makeDeps({ now: () => now });
    for (let i = 0; i < RATE_LIMIT_MAX_REQUESTS; i++) {
      await handleProxy(makeReq(), deps);
    }
    expect((await handleProxy(makeReq(), deps)).status).toBe(429);
    now += 5 * 60 * 1000 + 1;
    expect((await handleProxy(makeReq(), deps)).status).toBe(200);
  });
});

describe('handleProxy — CORS / methods', () => {
  it('answers OPTIONS preflight without checking auth, echoing the web app origin', async () => {
    const res = await handleProxy(
      makeReq({ method: 'OPTIONS', headers: { origin: 'https://cheaptripchip.vercel.app' } }),
      makeDeps(),
    );
    expect(res.status).toBe(204);
    expect(res.headers['Access-Control-Allow-Origin']).toBe('https://cheaptripchip.vercel.app');
    const allowed = res.headers['Access-Control-Allow-Headers'];
    expect(allowed).toContain('Authorization');
    expect(allowed).toContain('x-opencode-session');
    expect(allowed).toContain('Content-Type');
    expect(res.headers['Vary']).toBe('Origin');
  });

  it('allows localhost on any port for local web dev', async () => {
    for (const origin of ['http://localhost:5555', 'http://127.0.0.1:8080', 'http://localhost']) {
      const res = await handleProxy(
        makeReq({ headers: { authorization: `Bearer ${BASE_ENV.APP_TOKEN}`, origin } }),
        makeDeps(),
      );
      expect(res.status).toBe(200);
      expect(res.headers['Access-Control-Allow-Origin']).toBe(origin);
    }
  });

  it('gives other origins no Access-Control-Allow-Origin', async () => {
    for (const origin of ['https://evil.example', 'https://cheaptripchip.vercel.app.evil.example', 'http://localhost.evil.example']) {
      const res = await handleProxy(makeReq({ method: 'OPTIONS', headers: { origin } }), makeDeps());
      expect(res.status).toBe(204);
      expect(res.headers['Access-Control-Allow-Origin']).toBeUndefined();
    }
  });

  it('uses ALLOWED_ORIGINS instead of the default when set', async () => {
    const env = { ...BASE_ENV, ALLOWED_ORIGINS: 'https://other.vercel.app/, https://x.example' };
    const withOrigin = (origin: string) =>
      makeReq({ headers: { authorization: `Bearer ${BASE_ENV.APP_TOKEN}`, origin } });
    const ok = await handleProxy(withOrigin('https://other.vercel.app'), makeDeps({ env }));
    expect(ok.headers['Access-Control-Allow-Origin']).toBe('https://other.vercel.app');
    const old = await handleProxy(withOrigin('https://cheaptripchip.vercel.app'), makeDeps({ env }));
    expect(old.headers['Access-Control-Allow-Origin']).toBeUndefined();
  });

  it('keeps serving native (no Origin) requests unchanged, still gated by the app token', async () => {
    const ok = await handleProxy(makeReq(), makeDeps());
    expect(ok.status).toBe(200);
    expect(ok.headers['Access-Control-Allow-Origin']).toBeUndefined();
    const denied = await handleProxy(
      makeReq({ headers: { authorization: 'Bearer wrong', origin: 'https://cheaptripchip.vercel.app' } }),
      makeDeps(),
    );
    expect(denied.status).toBe(401);
    expect(denied.headers['Access-Control-Allow-Origin']).toBe('https://cheaptripchip.vercel.app');
  });

  it('rejects non-POST/OPTIONS methods', async () => {
    const res = await handleProxy(makeReq({ method: 'GET' }), makeDeps());
    expect(res.status).toBe(404);
  });
});

describe('handleProxy — upstream passthrough', () => {
  it('forwards to OpenCode Go with the server-side key, not the app token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ choices: [] }), { status: 200 }),
    );
    const req = makeReq();
    await handleProxy(req, makeDeps({ fetch: fetchMock }));

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe('https://opencode.ai/inference/go/v1/chat/completions');
    expect(url.startsWith(DEFAULT_UPSTREAM_BASE)).toBe(true);
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe(`Bearer ${BASE_ENV.OPENCODE_API_KEY}`);
    expect(headers['User-Agent']).toBe('cheaptripchip-api/1.0');
    expect(headers['Content-Type']).toBe('application/json');
    expect(JSON.stringify(headers)).not.toContain(BASE_ENV.APP_TOKEN);
    // The client's body must reach upstream byte-for-byte (unchanged shape).
    expect(JSON.parse(init.body as string)).toEqual(req.body);
  });

  it('honors OPENCODE_BASE_URL (trailing slash tolerated)', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
    await handleProxy(
      makeReq(),
      makeDeps({ fetch: fetchMock, env: { ...BASE_ENV, OPENCODE_BASE_URL: 'https://zen.example/x/' } }),
    );
    expect(fetchMock.mock.calls[0][0]).toBe('https://zen.example/x/v1/chat/completions');
  });

  it('returns 500 when OPENCODE_API_KEY is missing', async () => {
    const deps = makeDeps({ env: { APP_TOKEN: BASE_ENV.APP_TOKEN } });
    const res = await handleProxy(makeReq(), deps);
    expect(res.status).toBe(500);
    expect(res.body).toMatchObject({
      error: { code: 500, message: 'Proxy is missing OPENCODE_API_KEY' },
    });
    expect(deps.fetch).not.toHaveBeenCalled();
  });

  describe('x-opencode-session', () => {
    async function sentSession(headers: Record<string, string>, ip = '1.2.3.4') {
      const fetchMock = vi.fn().mockResolvedValue(new Response('{}', { status: 200 }));
      await handleProxy(
        makeReq({ headers: { authorization: `Bearer ${BASE_ENV.APP_TOKEN}`, ...headers }, ip }),
        makeDeps({ fetch: fetchMock }),
      );
      const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
      return (init.headers as Record<string, string>)['x-opencode-session'];
    }

    it('forwards a valid client session id', async () => {
      expect(await sentSession({ 'x-opencode-session': 'abc.DEF_123-x' })).toBe('abc.DEF_123-x');
    });

    it('derives a stable id from the IP when missing', async () => {
      const a = await sentSession({});
      expect(a).toMatch(/^cheaptripchip-[0-9a-f]{16}$/);
      expect(await sentSession({})).toBe(a);
      expect(await sentSession({}, '9.9.9.9')).not.toBe(a);
    });

    it('derives an id when the client value is invalid', async () => {
      for (const bad of ['has space', 'a/b', '', 'x'.repeat(129)]) {
        expect(await sentSession({ 'x-opencode-session': bad })).toMatch(/^cheaptripchip-[0-9a-f]{16}$/);
      }
    });
  });

  it('passes upstream status and body through unchanged on error', async () => {
    const upstreamBody = { type: 'error', error: { type: 'ModelError', message: 'Model not supported' } };
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify(upstreamBody), { status: 400 }),
    );
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(400);
    expect(res.body).toEqual(upstreamBody);
  });

  it('passes through a 503 unchanged (transient — app retries)', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { message: 'overloaded' } }), { status: 503 }),
    );
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(503);
  });

  it('wraps a non-JSON upstream body in an error object', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('<html>bad gateway</html>', { status: 502 }));
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
    expect(res.body).toMatchObject({ error: { message: '<html>bad gateway</html>' } });
  });

  it('returns 504 when upstream aborts (timeout)', async () => {
    const fetchMock = vi.fn().mockImplementation(() => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      return Promise.reject(err);
    });
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(504);
    expect(res.body).toMatchObject({ error: { status: 'DEADLINE_EXCEEDED' } });
  });

  it('returns 502 on a plain network failure', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error('network down'));
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
    expect(res.body).toMatchObject({ error: { status: 'UNAVAILABLE' } });
  });
});

function imageBody(count = 1, extra: Record<string, unknown> = {}) {
  const image = { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } };
  return chatBody({
    messages: [
      {
        role: 'user',
        content: [{ type: 'text', text: 'extract' }, ...Array.from({ length: count }, () => image)],
      },
    ],
    temperature: 0,
    ...extra,
  });
}

describe('image body cap', () => {
  it('counts image_url parts across messages, ignoring text', () => {
    expect(countInlineImages(imageBody(1))).toBe(1);
    expect(countInlineImages(imageBody(3))).toBe(3);
    expect(
      countInlineImages({
        messages: [
          { role: 'system', content: 'plain string' },
          { role: 'user', content: [{ type: 'text', text: 'hi' }] },
          { role: 'user', content: [{ type: 'image_url', image_url: { url: 'https://x/y.png' } }] },
        ],
      }),
    ).toBe(1);
    expect(countInlineImages(chatBody())).toBe(0);
    expect(countInlineImages({ messages: 'nope' })).toBe(0);
    expect(countInlineImages(undefined)).toBe(0);
  });

  it('accepts an image request well above the text cap', async () => {
    const res = await handleProxy(
      makeReq({ body: imageBody(), contentLength: 3 * 1024 * 1024 }),
      makeDeps(),
    );
    expect(res.status).toBe(200);
  });

  it('accepts an image request exactly at the image cap', async () => {
    const res = await handleProxy(
      makeReq({ body: imageBody(), contentLength: MAX_IMAGE_BODY_BYTES }),
      makeDeps(),
    );
    expect(res.status).toBe(200);
  });

  it('rejects an image request over the image cap with 413', async () => {
    const deps = makeDeps();
    const res = await handleProxy(
      makeReq({ body: imageBody(), contentLength: MAX_IMAGE_BODY_BYTES + 1 }),
      deps,
    );
    expect(res.status).toBe(413);
    expect(deps.fetch).not.toHaveBeenCalled();
  });

  it('keeps the small cap for a text-only body', async () => {
    const res = await handleProxy(makeReq({ contentLength: 65 * 1024 }), makeDeps());
    expect(res.status).toBe(413);
  });

  it('rejects more than MAX_INLINE_IMAGES images', async () => {
    const res = await handleProxy(
      makeReq({ body: imageBody(MAX_INLINE_IMAGES + 1) }),
      makeDeps(),
    );
    expect(res.status).toBe(413);
  });
});

describe('response cache', () => {
  const deterministic = chatBody({
    messages: [{ role: 'user', content: 'same prompt' }],
    temperature: 0,
  });

  it('serves an identical deterministic request from cache without calling upstream', async () => {
    const deps = makeDeps();
    const first = await handleProxy(makeReq({ body: deterministic }), deps);
    const second = await handleProxy(makeReq({ body: deterministic }), deps);
    expect(first.status).toBe(200);
    expect(first.headers['X-Cache']).toBe('MISS');
    expect(second.status).toBe(200);
    expect(second.headers['X-Cache']).toBe('HIT');
    expect(second.body).toEqual(first.body);
    expect(deps.fetch).toHaveBeenCalledTimes(1);
  });

  it('ignores the session header in the cache key', async () => {
    const deps = makeDeps();
    const auth = `Bearer ${BASE_ENV.APP_TOKEN}`;
    await handleProxy(
      makeReq({ body: deterministic, headers: { authorization: auth, 'x-opencode-session': 'one' } }),
      deps,
    );
    const again = await handleProxy(
      makeReq({ body: deterministic, headers: { authorization: auth, 'x-opencode-session': 'two' } }),
      deps,
    );
    expect(again.headers['X-Cache']).toBe('HIT');
    expect(deps.fetch).toHaveBeenCalledTimes(1);
  });

  it('misses for a different model or a different body', async () => {
    const deps = makeDeps();
    await handleProxy(makeReq({ body: deterministic }), deps);
    await handleProxy(makeReq({ body: { ...deterministic, model: 'mimo-v2.6-flash' } }), deps);
    await handleProxy(
      makeReq({ body: { ...deterministic, messages: [{ role: 'user', content: 'other prompt' }] } }),
      deps,
    );
    expect(deps.fetch).toHaveBeenCalledTimes(3);
  });

  it('expires entries after the TTL', async () => {
    let now = 1_000_000;
    const deps = makeDeps({ now: () => now });
    await handleProxy(makeReq({ body: deterministic }), deps);
    now += CACHE_TTL_MS - 1;
    const hit = await handleProxy(makeReq({ body: deterministic }), deps);
    expect(hit.headers['X-Cache']).toBe('HIT');
    now += 2;
    const miss = await handleProxy(makeReq({ body: deterministic }), deps);
    expect(miss.headers['X-Cache']).toBe('MISS');
    expect(deps.fetch).toHaveBeenCalledTimes(2);
  });

  it('does not cache non-200 responses', async () => {
    const fetchMock = vi.fn().mockImplementation(
      async () =>
        new Response(JSON.stringify({ error: { code: 503, message: 'busy' } }), { status: 503 }),
    );
    const deps = makeDeps({ fetch: fetchMock });
    await handleProxy(makeReq({ body: deterministic }), deps);
    const again = await handleProxy(makeReq({ body: deterministic }), deps);
    expect(again.status).toBe(503);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('does not cache sampled (non-zero / default temperature) requests', async () => {
    const deps = makeDeps();
    const sampled = { ...deterministic, temperature: 0.7 };
    await handleProxy(makeReq({ body: sampled }), deps);
    const again = await handleProxy(makeReq({ body: sampled }), deps);
    expect(again.headers['X-Cache']).toBeUndefined();
    await handleProxy(makeReq(), deps); // no temperature at all
    await handleProxy(makeReq(), deps);
    expect(deps.fetch).toHaveBeenCalledTimes(4);
  });

  it('caches image requests too', async () => {
    const deps = makeDeps();
    await handleProxy(makeReq({ body: imageBody() }), deps);
    const again = await handleProxy(makeReq({ body: imageBody() }), deps);
    expect(again.headers['X-Cache']).toBe('HIT');
    expect(deps.fetch).toHaveBeenCalledTimes(1);
  });

  it('still requires a valid token for a cached request', async () => {
    const deps = makeDeps();
    await handleProxy(makeReq({ body: deterministic }), deps);
    const res = await handleProxy(
      makeReq({ body: deterministic, headers: { authorization: 'Bearer wrong' } }),
      deps,
    );
    expect(res.status).toBe(401);
  });

  it('evicts the least-recently-used entry beyond CACHE_MAX_ENTRIES', async () => {
    const deps = makeDeps();
    const body = (i: number) =>
      chatBody({ messages: [{ role: 'user', content: `prompt ${i}` }], temperature: 0 });
    for (let i = 0; i <= CACHE_MAX_ENTRIES; i++) {
      await handleProxy(makeReq({ body: body(i), ip: `10.0.${Math.floor(i / 25)}.${i % 25}` }), deps);
    }
    // Entry 0 was the oldest and got evicted; entry CACHE_MAX_ENTRIES is still cached.
    const evicted = await handleProxy(makeReq({ body: body(0), ip: '9.9.9.1' }), deps);
    const kept = await handleProxy(makeReq({ body: body(CACHE_MAX_ENTRIES), ip: '9.9.9.2' }), deps);
    expect(evicted.headers['X-Cache']).toBe('MISS');
    expect(kept.headers['X-Cache']).toBe('HIT');
  });
});

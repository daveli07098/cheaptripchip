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
  parseModelAction,
  resetRateLimiter,
  resetResponseCache,
  type ProxyDeps,
  type ProxyRequest,
} from '../lib/proxy.js';

const BASE_ENV = {
  APP_TOKEN: 'test-app-token',
  GEMINI_API_KEY: 'real-gemini-key',
};

function makeReq(overrides: Partial<ProxyRequest> = {}): ProxyRequest {
  return {
    method: 'POST',
    modelAction: 'gemini-3.5-flash:generateContent',
    query: { key: BASE_ENV.APP_TOKEN },
    headers: {},
    body: { contents: [{ parts: [{ text: 'hi' }] }] },
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
        JSON.stringify({ candidates: [{ content: { parts: [{ text: 'ok' }] } }] }),
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

describe('parseModelAction', () => {
  it('splits model and action on the colon', () => {
    expect(parseModelAction('gemini-3.5-flash:generateContent')).toEqual({
      model: 'gemini-3.5-flash',
      action: 'generateContent',
    });
  });

  it('handles model ids with dots/dashes before the colon', () => {
    expect(parseModelAction('gemini-3.1-flash-lite:generateContent')).toEqual({
      model: 'gemini-3.1-flash-lite',
      action: 'generateContent',
    });
  });

  it('returns null with no colon', () => {
    expect(parseModelAction('gemini-3.5-flash')).toBeNull();
  });

  it('decodes a percent-encoded colon, in case a rewrite ever encodes it', () => {
    expect(parseModelAction('gemini-3.5-flash%3AgenerateContent')).toEqual({
      model: 'gemini-3.5-flash',
      action: 'generateContent',
    });
  });

  it('returns null for undefined', () => {
    expect(parseModelAction(undefined)).toBeNull();
  });
});

describe('handleProxy — model allow-list', () => {
  it('allows every default model', async () => {
    for (const model of DEFAULT_ALLOWED_MODELS) {
      const res = await handleProxy(
        makeReq({ modelAction: `${model}:generateContent` }),
        makeDeps(),
      );
      expect(res.status).toBe(200);
    }
  });

  it('rejects a model not on the list with a Gemini-shaped 404', async () => {
    const res = await handleProxy(
      makeReq({ modelAction: 'gemini-9000-ultra:generateContent' }),
      makeDeps(),
    );
    expect(res.status).toBe(404);
    expect(res.body).toMatchObject({ error: { code: 404, status: 'NOT_FOUND' } });
  });

  it('rejects an action other than generateContent', async () => {
    const res = await handleProxy(
      makeReq({ modelAction: 'gemini-3.5-flash:streamGenerateContent' }),
      makeDeps(),
    );
    expect(res.status).toBe(404);
  });

  it('honors a custom ALLOWED_MODELS env override', async () => {
    const res = await handleProxy(
      makeReq({ modelAction: 'custom-model:generateContent' }),
      makeDeps({ env: { ...BASE_ENV, ALLOWED_MODELS: 'custom-model' } }),
    );
    expect(res.status).toBe(200);
  });
});

describe('handleProxy — auth', () => {
  it('rejects a missing token with 401', async () => {
    const res = await handleProxy(makeReq({ query: {} }), makeDeps());
    expect(res.status).toBe(401);
    expect(res.body).toMatchObject({ error: { code: 401 } });
  });

  it('rejects a wrong token with 401', async () => {
    const res = await handleProxy(makeReq({ query: { key: 'wrong' } }), makeDeps());
    expect(res.status).toBe(401);
  });

  it('accepts the token via x-goog-api-key header too', async () => {
    const res = await handleProxy(
      makeReq({ query: {}, headers: { 'x-goog-api-key': BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(res.status).toBe(200);
  });
});

describe('handleProxy — body size cap', () => {
  it('rejects an oversized body via content-length', async () => {
    const res = await handleProxy(
      makeReq({ contentLength: MAX_BODY_BYTES + 1 }),
      makeDeps(),
    );
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
      makeReq({ method: 'OPTIONS', query: {}, headers: { origin: 'https://cheaptripchip.vercel.app' } }),
      makeDeps(),
    );
    expect(res.status).toBe(204);
    expect(res.headers['Access-Control-Allow-Origin']).toBe('https://cheaptripchip.vercel.app');
    expect(res.headers['Access-Control-Allow-Headers']).toContain('Content-Type');
    expect(res.headers['Vary']).toBe('Origin');
  });

  it('allows localhost on any port for local web dev', async () => {
    for (const origin of ['http://localhost:5555', 'http://127.0.0.1:8080', 'http://localhost']) {
      const res = await handleProxy(makeReq({ headers: { origin } }), makeDeps());
      expect(res.status).toBe(200);
      expect(res.headers['Access-Control-Allow-Origin']).toBe(origin);
    }
  });

  it('gives other origins no Access-Control-Allow-Origin', async () => {
    for (const origin of ['https://evil.example', 'https://cheaptripchip.vercel.app.evil.example', 'http://localhost.evil.example']) {
      const res = await handleProxy(
        makeReq({ method: 'OPTIONS', query: {}, headers: { origin } }),
        makeDeps(),
      );
      expect(res.status).toBe(204);
      expect(res.headers['Access-Control-Allow-Origin']).toBeUndefined();
    }
  });

  it('uses ALLOWED_ORIGINS instead of the default when set', async () => {
    const env = { ...BASE_ENV, ALLOWED_ORIGINS: 'https://other.vercel.app/, https://x.example' };
    const ok = await handleProxy(
      makeReq({ headers: { origin: 'https://other.vercel.app' } }),
      makeDeps({ env }),
    );
    expect(ok.headers['Access-Control-Allow-Origin']).toBe('https://other.vercel.app');
    const old = await handleProxy(
      makeReq({ headers: { origin: 'https://cheaptripchip.vercel.app' } }),
      makeDeps({ env }),
    );
    expect(old.headers['Access-Control-Allow-Origin']).toBeUndefined();
  });

  it('keeps serving native (no Origin) requests unchanged, still gated by the app token', async () => {
    const ok = await handleProxy(makeReq(), makeDeps());
    expect(ok.status).toBe(200);
    expect(ok.headers['Access-Control-Allow-Origin']).toBeUndefined();
    const denied = await handleProxy(
      makeReq({ query: { key: 'wrong' }, headers: { origin: 'https://cheaptripchip.vercel.app' } }),
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
  it('forwards to the real Gemini endpoint with the server-side key, not the app token', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ candidates: [] }), { status: 200 }),
    );
    const req = makeReq();
    await handleProxy(req, makeDeps({ fetch: fetchMock }));

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent',
    );
    const headers = init.headers as Record<string, string>;
    expect(headers['x-goog-api-key']).toBe(BASE_ENV.GEMINI_API_KEY);
    expect(headers['Content-Type']).toBe('application/json');
    expect(url).not.toContain(BASE_ENV.APP_TOKEN);
    // The client's body must reach Gemini byte-for-byte (unchanged shape) —
    // this is the contract the app's extraction prompt actually depends on.
    expect(JSON.parse(init.body as string)).toEqual(req.body);
  });

  it('passes upstream status and body through unchanged on error, so the app cascade still works', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({ error: { code: 400, message: 'User location is not supported for the API use.' } }),
        { status: 400 },
      ),
    );
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(400);
    expect(res.body).toMatchObject({
      error: { message: 'User location is not supported for the API use.' },
    });
  });

  it('passes through a 503 unchanged (transient — app cascade retries)', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { message: 'overloaded' } }), { status: 503 }),
    );
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(503);
  });

  it('returns 504 Gemini-shaped error when upstream aborts (timeout)', async () => {
    const fetchMock = vi.fn().mockImplementation(() => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      return Promise.reject(err);
    });
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(504);
    expect(res.body).toMatchObject({ error: { status: 'DEADLINE_EXCEEDED' } });
  });

  it('returns 502 Gemini-shaped error on a plain network failure', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error('network down'));
    const res = await handleProxy(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
    expect(res.body).toMatchObject({ error: { status: 'UNAVAILABLE' } });
  });
});

function imageBody(mimeKey: 'inline_data' | 'inlineData' = 'inline_data', count = 1) {
  const image =
    mimeKey === 'inline_data'
      ? { inline_data: { mime_type: 'image/jpeg', data: 'AAAA' } }
      : { inlineData: { mimeType: 'image/png', data: 'AAAA' } };
  return {
    contents: [{ parts: [{ text: 'extract' }, ...Array.from({ length: count }, () => image)] }],
    generationConfig: { temperature: 0 },
  };
}

describe('image body cap', () => {
  it('counts inline images in both spellings, ignoring non-image inline data', () => {
    expect(countInlineImages(imageBody('inline_data'))).toBe(1);
    expect(countInlineImages(imageBody('inlineData', 2))).toBe(2);
    expect(
      countInlineImages({
        contents: [{ parts: [{ inline_data: { mime_type: 'application/pdf', data: 'x' } }] }],
      }),
    ).toBe(0);
    expect(countInlineImages({ contents: [{ parts: [{ text: 'hi' }] }] })).toBe(0);
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
      makeReq({ body: imageBody('inline_data', MAX_INLINE_IMAGES + 1) }),
      makeDeps(),
    );
    expect(res.status).toBe(413);
  });
});

describe('response cache', () => {
  const deterministic = {
    contents: [{ parts: [{ text: 'same prompt' }] }],
    generationConfig: { temperature: 0 },
  };

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

  it('misses for a different model or a different body', async () => {
    const deps = makeDeps();
    await handleProxy(makeReq({ body: deterministic }), deps);
    await handleProxy(
      makeReq({ body: deterministic, modelAction: 'gemini-3.8-flash:generateContent' }),
      deps,
    );
    await handleProxy(
      makeReq({
        body: { ...deterministic, contents: [{ parts: [{ text: 'other prompt' }] }] },
      }),
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
    const sampled = { ...deterministic, generationConfig: { temperature: 0.7 } };
    await handleProxy(makeReq({ body: sampled }), deps);
    const again = await handleProxy(makeReq({ body: sampled }), deps);
    expect(again.headers['X-Cache']).toBeUndefined();
    await handleProxy(makeReq(), deps); // no generationConfig at all
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
    const res = await handleProxy(makeReq({ body: deterministic, query: { key: 'wrong' } }), deps);
    expect(res.status).toBe(401);
  });

  it('evicts the least-recently-used entry beyond CACHE_MAX_ENTRIES', async () => {
    const deps = makeDeps();
    const body = (i: number) => ({
      contents: [{ parts: [{ text: `prompt ${i}` }] }],
      generationConfig: { temperature: 0 },
    });
    for (let i = 0; i <= CACHE_MAX_ENTRIES; i++) {
      await handleProxy(makeReq({ body: body(i), ip: `10.0.${Math.floor(i / 25)}.${i % 25}` }), deps);
    }
    // Entry 0 was the oldest and got evicted; entry CACHE_MAX_ENTRIES is still cached.
    const evicted = await handleProxy(makeReq({ body: body(0), ip: '9.9.9.1' }), deps);
    const kept = await handleProxy(
      makeReq({ body: body(CACHE_MAX_ENTRIES), ip: '9.9.9.2' }),
      deps,
    );
    expect(evicted.headers['X-Cache']).toBe('MISS');
    expect(kept.headers['X-Cache']).toBe('HIT');
  });
});

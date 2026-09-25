import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
  DEFAULT_ALLOWED_MODELS,
  MAX_BODY_BYTES,
  RATE_LIMIT_MAX_REQUESTS,
  handleProxy,
  parseModelAction,
  resetRateLimiter,
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
  it('answers OPTIONS preflight without checking auth', async () => {
    const res = await handleProxy(makeReq({ method: 'OPTIONS', query: {} }), makeDeps());
    expect(res.status).toBe(204);
    expect(res.headers['Access-Control-Allow-Origin']).toBe('*');
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

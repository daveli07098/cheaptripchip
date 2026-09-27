import { beforeEach, describe, expect, it, vi } from 'vitest';
import { handleMeta, MAX_REDIRECTS, type MetaDeps, type MetaRequest } from '../lib/meta.js';
import { resetRateLimiter } from '../lib/proxy.js';

const BASE_ENV = { APP_TOKEN: 'test-app-token' };
const IG_URL = 'https://www.instagram.com/p/abc123/';

function makeReq(overrides: Partial<MetaRequest> = {}): MetaRequest {
  return {
    method: 'GET',
    query: { url: IG_URL, key: BASE_ENV.APP_TOKEN },
    headers: {},
    ip: '1.2.3.4',
    ...overrides,
  };
}

function htmlResponse(html: string, status = 200): Response {
  return new Response(html, { status, headers: { 'Content-Type': 'text/html' } });
}

function makeDeps(overrides: Partial<MetaDeps> = {}): MetaDeps {
  const defaultFetch = vi
    .fn()
    .mockImplementation(async () =>
      htmlResponse(
        '<meta property="og:title" content="Name on Instagram: &quot;caption&quot;">' +
          '<meta property="og:description" content="123 likes - name on Jan 1, 2024: &quot;desc&quot;">' +
          '<meta property="og:image" content="https://example.com/img.jpg">',
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

describe('handleMeta — method / CORS', () => {
  it('answers OPTIONS preflight without auth', async () => {
    const res = await handleMeta(
      makeReq({ method: 'OPTIONS', query: {}, headers: { origin: 'https://cheaptripchip.vercel.app' } }),
      makeDeps(),
    );
    expect(res.status).toBe(204);
    expect(res.headers['Access-Control-Allow-Origin']).toBe('https://cheaptripchip.vercel.app');
    expect(res.headers['Access-Control-Allow-Methods']).toBe('GET, OPTIONS');
  });

  it('rejects non-GET/OPTIONS with 405', async () => {
    const res = await handleMeta(makeReq({ method: 'POST' }), makeDeps());
    expect(res.status).toBe(405);
  });
});

describe('handleMeta — auth', () => {
  it('rejects a missing token with 401', async () => {
    const res = await handleMeta(makeReq({ query: { url: IG_URL } }), makeDeps());
    expect(res.status).toBe(401);
  });

  it('rejects a wrong token with 401', async () => {
    const res = await handleMeta(makeReq({ query: { url: IG_URL, key: 'wrong' } }), makeDeps());
    expect(res.status).toBe(401);
  });

  it('accepts the token via x-goog-api-key header too', async () => {
    const res = await handleMeta(
      makeReq({ query: { url: IG_URL }, headers: { 'x-goog-api-key': BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(res.status).toBe(200);
  });

  it('does not fetch when the token is wrong', async () => {
    const deps = makeDeps();
    await handleMeta(makeReq({ query: { url: IG_URL, key: 'wrong' } }), deps);
    expect(deps.fetch).not.toHaveBeenCalled();
  });
});

describe('handleMeta — host allow-list', () => {
  it('allows every supported host', async () => {
    for (const url of [
      'https://www.instagram.com/p/abc/',
      'https://instagram.com/p/abc/',
      'https://www.tiktok.com/@user/video/1',
      'https://tiktok.com/@user/video/1',
      'https://vt.tiktok.com/abc/',
      'https://vm.tiktok.com/abc/',
    ]) {
      const res = await handleMeta(makeReq({ query: { url, key: BASE_ENV.APP_TOKEN } }), makeDeps());
      expect(res.status, url).toBe(200);
    }
  });

  it('rejects a disallowed host with 400', async () => {
    const res = await handleMeta(
      makeReq({ query: { url: 'https://example.com/p/abc/', key: BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(res.status).toBe(400);
  });

  it('rejects a non-https scheme', async () => {
    const res = await handleMeta(
      makeReq({ query: { url: 'http://www.instagram.com/p/abc/', key: BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(res.status).toBe(400);
  });

  it('rejects an unparseable url', async () => {
    const res = await handleMeta(
      makeReq({ query: { url: 'not a url', key: BASE_ENV.APP_TOKEN } }),
      makeDeps(),
    );
    expect(res.status).toBe(400);
  });

  it('rejects a missing url parameter', async () => {
    const res = await handleMeta(makeReq({ query: { key: BASE_ENV.APP_TOKEN } }), makeDeps());
    expect(res.status).toBe(400);
  });

  it('does not fetch a disallowed host at all', async () => {
    const deps = makeDeps();
    await handleMeta(makeReq({ query: { url: 'https://example.com/p/abc/', key: BASE_ENV.APP_TOKEN } }), deps);
    expect(deps.fetch).not.toHaveBeenCalled();
  });
});

describe('handleMeta — redirects', () => {
  it('follows a same-allow-list redirect and returns the final url', async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(async () =>
        new Response(null, {
          status: 301,
          headers: { location: 'https://www.tiktok.com/@user/video/123' },
        }),
      )
      .mockImplementationOnce(async () =>
        htmlResponse('<meta property="og:title" content="TikTok caption">'),
      );
    const res = await handleMeta(
      makeReq({ query: { url: 'https://vm.tiktok.com/ZM123/', key: BASE_ENV.APP_TOKEN } }),
      makeDeps({ fetch: fetchMock }),
    );
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      title: 'TikTok caption',
      finalUrl: 'https://www.tiktok.com/@user/video/123',
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('blocks a redirect to a disallowed host', async () => {
    const fetchMock = vi.fn().mockImplementationOnce(async () =>
      new Response(null, { status: 302, headers: { location: 'https://evil.example/phish' } }),
    );
    const res = await handleMeta(
      makeReq({ query: { url: IG_URL, key: BASE_ENV.APP_TOKEN } }),
      makeDeps({ fetch: fetchMock }),
    );
    expect(res.status).toBe(400);
  });

  it('gives up after MAX_REDIRECTS hops with a 502', async () => {
    const fetchMock = vi.fn().mockImplementation(async () =>
      new Response(null, { status: 302, headers: { location: IG_URL } }),
    );
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
    expect(fetchMock).toHaveBeenCalledTimes(MAX_REDIRECTS + 1);
  });
});

describe('handleMeta — rate limiting', () => {
  it('429s after the shared limiter trips, with its own "meta:" key prefix', async () => {
    const deps = makeDeps();
    for (let i = 0; i < 30; i++) {
      const res = await handleMeta(makeReq({ ip: 'ip-meta' }), deps);
      expect(res.status).toBe(200);
    }
    const blocked = await handleMeta(makeReq({ ip: 'ip-meta' }), deps);
    expect(blocked.status).toBe(429);
  });
});

describe('handleMeta — parsing', () => {
  it('parses og:title/og:description/og:image', async () => {
    const res = await handleMeta(makeReq(), makeDeps());
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      title: 'Name on Instagram: "caption"',
      description: '123 likes - name on Jan 1, 2024: "desc"',
      image: 'https://example.com/img.jpg',
    });
  });

  it('falls back to <meta name="description"> for TikTok pages', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(htmlResponse('<meta name="description" content="a tiktok description">'));
    const res = await handleMeta(
      makeReq({ query: { url: 'https://www.tiktok.com/@user/video/1', key: BASE_ENV.APP_TOKEN } }),
      makeDeps({ fetch: fetchMock }),
    );
    expect(res.body).toMatchObject({ title: null, description: 'a tiktok description' });
  });

  it('decodes HTML entities', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(htmlResponse('<meta property="og:title" content="craving &#x1F35C; at &amp;spot">'));
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.body).toMatchObject({ title: 'craving \u{1F35C} at &spot' });
  });

  it('returns 200 with nulls when the page has no usable tags', async () => {
    const fetchMock = vi.fn().mockResolvedValue(htmlResponse('<html><head><title>Login</title></head></html>'));
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ title: null, description: null, image: null });
  });

  it('returns 502 for a non-2xx upstream status', async () => {
    const fetchMock = vi.fn().mockResolvedValue(htmlResponse('not found', 404));
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
  });

  it('caps the response body and still parses what fits', async () => {
    const padding = 'x'.repeat(2 * 1024 * 1024);
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        htmlResponse(`<meta property="og:title" content="short title">${padding}`),
      );
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ title: 'short title' });
  });

  it('returns 504 on a fetch timeout', async () => {
    const fetchMock = vi.fn().mockImplementation(() => {
      const err = new Error('aborted');
      err.name = 'AbortError';
      return Promise.reject(err);
    });
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(504);
  });

  it('returns 502 on a plain network failure', async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error('network down'));
    const res = await handleMeta(makeReq(), makeDeps({ fetch: fetchMock }));
    expect(res.status).toBe(502);
  });
});

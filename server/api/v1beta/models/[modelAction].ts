/**
 * Vercel adapter for POST /v1beta/models/<model>:generateContent (also reachable
 * at /api/v1beta/models/<model>:generateContent directly — see vercel.json rewrite).
 *
 * Thin req/res translation only; all logic lives in ../../../lib/proxy.ts so it
 * can be unit-tested without Vercel types.
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { handleProxy, type ProxyRequest } from '../../../lib/proxy.js';

function firstHeader(
  headers: VercelRequest['headers'],
  name: string,
): string | undefined {
  const v = headers[name];
  return Array.isArray(v) ? v[0] : v;
}

function clientIp(req: VercelRequest): string {
  const forwardedFor = firstHeader(req.headers, 'x-forwarded-for');
  const first = forwardedFor?.split(',')[0]?.trim();
  return first || firstHeader(req.headers, 'x-real-ip') || 'unknown';
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const modelActionParam = req.query.modelAction;
  const modelAction = Array.isArray(modelActionParam) ? modelActionParam[0] : modelActionParam;
  const contentLengthHeader = firstHeader(req.headers, 'content-length');

  const proxyReq: ProxyRequest = {
    method: req.method ?? 'GET',
    modelAction,
    query: req.query as ProxyRequest['query'],
    headers: req.headers as ProxyRequest['headers'],
    body: req.body,
    contentLength: contentLengthHeader ? Number(contentLengthHeader) : undefined,
    ip: clientIp(req),
  };

  const result = await handleProxy(proxyReq, { fetch, now: Date.now, env: process.env });

  for (const [key, value] of Object.entries(result.headers)) {
    res.setHeader(key, value);
  }
  res.status(result.status);
  if (result.body === undefined) {
    res.end();
    return;
  }
  res.json(result.body);
}

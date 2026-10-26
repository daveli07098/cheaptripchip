/**
 * Vercel adapter for GET /api/meta?url=<encoded post url>&key=<APP_TOKEN>.
 *
 * Thin req/res translation only; all logic lives in ../lib/meta.ts so it can
 * be unit-tested without Vercel types (same split as
 * api/v1/chat/completions.ts / lib/proxy.ts).
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { handleMeta, type MetaRequest } from '../lib/meta.js';

function firstHeader(headers: VercelRequest['headers'], name: string): string | undefined {
  const v = headers[name];
  return Array.isArray(v) ? v[0] : v;
}

function clientIp(req: VercelRequest): string {
  const forwardedFor = firstHeader(req.headers, 'x-forwarded-for');
  const first = forwardedFor?.split(',')[0]?.trim();
  return first || firstHeader(req.headers, 'x-real-ip') || 'unknown';
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const metaReq: MetaRequest = {
    method: req.method ?? 'GET',
    query: req.query as MetaRequest['query'],
    headers: req.headers as MetaRequest['headers'],
    ip: clientIp(req),
  };

  const result = await handleMeta(metaReq, { fetch, now: Date.now, env: process.env });

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

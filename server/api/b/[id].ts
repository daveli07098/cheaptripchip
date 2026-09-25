/**
 * Vercel adapter for GET /b/:id?c=<code> (vercel.json rewrites /b/:id here).
 * Thin req/res translation only; the page lives in ../../lib/board_page.ts.
 */
import type { VercelRequest, VercelResponse } from '@vercel/node';
import { renderBoardPage } from '../../lib/board_page.js';

function first(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

export default function handler(req: VercelRequest, res: VercelResponse) {
  const result = renderBoardPage(req.method ?? 'GET', first(req.query.id), first(req.query.c));
  for (const [key, value] of Object.entries(result.headers)) {
    res.setHeader(key, value);
  }
  res.status(result.status);
  if (req.method === 'HEAD') {
    res.end();
    return;
  }
  res.send(result.body);
}

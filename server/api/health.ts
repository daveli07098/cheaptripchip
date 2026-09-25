/** GET /api/health — confirms the deployment and its region (should read "hnd1"). */
import type { VercelRequest, VercelResponse } from '@vercel/node';

export default function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.status(204).end();
    return;
  }
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.status(200).json({ ok: true, region: process.env.VERCEL_REGION ?? null });
}

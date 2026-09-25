/**
 * GET /b/:id?c=<inviteCode> — the landing page behind shared-board invite
 * links (lib/services/board_invite_link.dart in the app).
 *
 * It exposes NO board data (the server never reads Firestore): it only hands
 * the id and code back to the app through the custom scheme
 * cheaptripchip://board/<id>?c=<code>. On Android with the app installed,
 * verified App Links (public/.well-known/assetlinks.json) skip this page
 * entirely. Pure function so vitest can exercise it without Vercel types.
 */
import { createHash } from 'node:crypto';

export interface PageResult {
  status: number;
  headers: Record<string, string>;
  body: string;
}

/** Board ids are Firestore auto-ids; invite codes are base-62. */
const TOKEN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Static (so it can be pinned by hash in the CSP): tries the app link once
 * on load. Browsers that block a scripted jump to a custom scheme (Chrome on
 * Android without a user gesture) still have the button.
 */
export const REDIRECT_SCRIPT =
  "setTimeout(function(){var a=document.getElementById('open');if(a){location.href=a.href;}},100);";

const SCRIPT_HASH = createHash('sha256').update(REDIRECT_SCRIPT).digest('base64');

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function headers(): Record<string, string> {
  return {
    'Content-Type': 'text/html; charset=utf-8',
    // The URL carries an invite secret: never cache, index, or leak it.
    'Cache-Control': 'no-store',
    'X-Robots-Tag': 'noindex, nofollow',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': [
      "default-src 'none'",
      "style-src 'unsafe-inline'",
      `script-src 'sha256-${SCRIPT_HASH}'`,
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join('; '),
  };
}

function page(title: string, main: string, script = ''): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>${escapeHtml(title)}</title>
<style>
body{font-family:system-ui,-apple-system,sans-serif;margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff5f6;color:#222}
main{max-width:360px;padding:32px 24px;text-align:center}
h1{font-size:22px;margin:12px 0 8px}
p{line-height:1.5;color:#555}
.btn{display:inline-block;margin:16px 0;padding:14px 22px;border-radius:999px;background:#ff5a6e;color:#fff;font-weight:700;text-decoration:none}
small{color:#888}
</style>
</head>
<body>
<main>
${main}
</main>${script ? `\n<script>${script}</script>` : ''}
</body>
</html>
`;
}

export function renderBoardPage(
  method: string,
  id: string | undefined,
  code: string | undefined,
): PageResult {
  if (method !== 'GET' && method !== 'HEAD') {
    return {
      status: 405,
      headers: { ...headers(), Allow: 'GET, HEAD' },
      body: page('Not allowed', '<h1>Not allowed</h1>'),
    };
  }
  if (!id || !code || !TOKEN.test(id) || !TOKEN.test(code)) {
    return {
      status: 404,
      headers: headers(),
      body: page(
        'Link not valid',
        `<div aria-hidden="true" style="font-size:40px">📌</div>
<h1>This link isn't valid</h1>
<p>Ask the person who shared it to send the board link again.</p>`,
      ),
    };
  }
  const appLink = `cheaptripchip://board/${encodeURIComponent(id)}?c=${encodeURIComponent(code)}`;
  return {
    status: 200,
    headers: headers(),
    body: page(
      'Open in CheapTripChip',
      `<div aria-hidden="true" style="font-size:40px">📌</div>
<h1>You're invited to a board</h1>
<p>Someone shared a CheapTripChip board with you. Open it in the app and sign in to join.</p>
<a id="open" class="btn" href="${escapeHtml(appLink)}">Open in CheapTripChip</a>
<p><small>Get the app: CheapTripChip isn't in the app stores yet — ask the person who shared this board for an install link, then open this link again.</small></p>`,
      REDIRECT_SCRIPT,
    ),
  };
}

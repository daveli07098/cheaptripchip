import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { REDIRECT_SCRIPT, escapeHtml, renderBoardPage } from '../lib/board_page.js';

const ID = 'AbC123xyz_-Q';
const CODE = 'k9Zq2LmN8pR4sT6vW0xY1aB3';

describe('renderBoardPage', () => {
  it('links to the app with the id and code and nothing else', () => {
    const res = renderBoardPage('GET', ID, CODE);
    expect(res.status).toBe(200);
    expect(res.body).toContain(`href="cheaptripchip://board/${ID}?c=${CODE}"`);
    expect(res.body).toContain('Open in CheapTripChip');
    expect(res.body).toContain('Get the app');
    // The code appears only inside the app link — never as page text.
    expect(res.body.split(CODE)).toHaveLength(2);
    expect(res.body.split(ID)).toHaveLength(2);
  });

  it('sets no-store, noindex, no-referrer and a hash-pinned CSP', () => {
    const { headers } = renderBoardPage('GET', ID, CODE);
    expect(headers['Content-Type']).toBe('text/html; charset=utf-8');
    expect(headers['Cache-Control']).toBe('no-store');
    expect(headers['X-Robots-Tag']).toContain('noindex');
    expect(headers['Referrer-Policy']).toBe('no-referrer');
    const hash = createHash('sha256').update(REDIRECT_SCRIPT).digest('base64');
    expect(headers['Content-Security-Policy']).toContain(`script-src 'sha256-${hash}'`);
    expect(headers['Content-Security-Policy']).toContain("default-src 'none'");
  });

  it('embeds exactly the hashed script', () => {
    const { body } = renderBoardPage('GET', ID, CODE);
    expect(body).toContain(`<script>${REDIRECT_SCRIPT}</script>`);
    expect(body.match(/<script/g)).toHaveLength(1);
  });

  it.each([
    ['<script>alert(1)</script>', CODE],
    ['"onmouseover="x', CODE],
    [ID, '"><img src=x onerror=alert(1)>'],
    [ID, 'short code with spaces'],
    ['a/b', CODE],
    [ID, undefined],
    [undefined, CODE],
    ['', ''],
  ])('rejects malformed id=%j code=%j without echoing it', (id, code) => {
    const res = renderBoardPage('GET', id, code);
    expect(res.status).toBe(404);
    expect(res.body).not.toContain('cheaptripchip://');
    expect(res.body).not.toContain('<img');
    expect(res.body).not.toContain('alert(');
    expect(res.body).not.toContain('<script');
  });

  it('rejects non-GET methods', () => {
    const res = renderBoardPage('POST', ID, CODE);
    expect(res.status).toBe(405);
    expect(res.headers.Allow).toBe('GET, HEAD');
    expect(res.body).not.toContain(CODE);
  });

  it('allows HEAD', () => {
    expect(renderBoardPage('HEAD', ID, CODE).status).toBe(200);
  });
});

describe('escapeHtml', () => {
  it('escapes every HTML-significant character', () => {
    expect(escapeHtml(`<a href="x" title='y'>&</a>`)).toBe(
      '&lt;a href=&quot;x&quot; title=&#39;y&#39;&gt;&amp;&lt;/a&gt;',
    );
  });
});

describe('assetlinks.json', () => {
  const statements = JSON.parse(
    readFileSync(new URL('../public/.well-known/assetlinks.json', import.meta.url), 'utf8'),
  );

  it('delegates all URLs to the Android app', () => {
    expect(Array.isArray(statements)).toBe(true);
    expect(statements).toHaveLength(1);
    const [statement] = statements;
    expect(statement.relation).toEqual(['delegate_permission/common.handle_all_urls']);
    expect(statement.target.namespace).toBe('android_app');
    expect(statement.target.package_name).toBe('com.cheaptripchip.cheaptripchip');
  });

  it('lists well-formed SHA-256 certificate fingerprints', () => {
    const fingerprints: string[] = statements[0].target.sha256_cert_fingerprints;
    expect(fingerprints.length).toBeGreaterThan(0);
    for (const fingerprint of fingerprints) {
      expect(fingerprint).toMatch(/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/);
    }
  });
});

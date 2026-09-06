import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const config = JSON.parse(readFileSync(new URL('../firebase.json', import.meta.url)));
const headers = Object.fromEntries(config.hosting.headers.filter(rule => rule.source === '**').flatMap(rule => rule.headers).map(({ key, value }) => [key.toLowerCase(), value]));
test('Hosting restricts execution, framing, connections and browser permissions', () => {
  const csp = headers['content-security-policy'] ?? '';
  for (const directive of ["default-src 'self'", "script-src 'self' 'wasm-unsafe-eval'", "connect-src 'self'", "frame-ancestors 'none'", "object-src 'none'", "base-uri 'none'", "form-action 'none'"]) assert.ok(csp.split(';').map(value => value.trim()).includes(directive), directive);
  assert.equal(headers['x-frame-options'], 'DENY');
  assert.equal(headers['x-content-type-options'], 'nosniff');
  assert.equal(headers['referrer-policy'], 'no-referrer');
  assert.match(headers['permissions-policy'], /microphone=\(self\)/);
  assert.match(headers['permissions-policy'], /camera=\(\)/);
});
test('dynamic JavaScript is allowed only for the fixed Vosk worker', () => {
  const exceptions = config.hosting.headers.filter(rule => rule.headers.some(header => header.value.includes("'unsafe-eval'")));
  assert.equal(exceptions.length, 1);
  assert.equal(exceptions[0].source, '/speech/vosk-0.0.3/vosk.worker.js');
});

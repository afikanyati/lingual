/** Real local Whisper + browser microphone regression. Uses synthetic speech, never the user's mic. */
import { chromium } from '../web/node_modules/playwright-core/index.mjs';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync } from 'node:fs';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';

mkdirSync('.local/logs', { recursive: true });
const fixture = resolve(process.env.SPEECH_FIXTURE || '.local/speech-check.wav');
if (!process.env.SPEECH_FIXTURE) {
  execFileSync('say', ['-o', '.local/speech-check.aiff', 'Lingual gives my thoughts a little room to grow. I can speak freely and edit my words.']);
  execFileSync('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', '.local/speech-check.aiff', fixture]);
}
const targetURL = process.env.LINGUAL_TEST_URL || 'http://127.0.0.1:5174';
const origin = new URL(targetURL).origin;
const profile = mkdtempSync(resolve('.local/speech-static-profile-'));
const context = await chromium.launchPersistentContext(profile, {
  headless: true, viewport: { width: 1440, height: 1100 },
  args: ['--autoplay-policy=no-user-gesture-required', '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', `--use-file-for-fake-audio-capture=${fixture}`],
});
const page = context.pages()[0];
const errors = []; const uploads = []; const modelDownloads = []; const externalSpeechRequests = [];
let requireCachedModel = false;
// All external hosts are blocked. Fonts may fail to load; the speech engine must remain fully functional.
await context.route('**/*', async route => {
  const url = new URL(route.request().url());
  if (url.origin !== origin) {
    if (!['fonts.googleapis.com', 'fonts.gstatic.com'].includes(url.hostname)) externalSpeechRequests.push(url.href);
    await route.abort();
    return;
  }
  if (url.pathname.includes('/models/')) {
    modelDownloads.push(url.href);
    if (requireCachedModel) { await route.abort(); return; }
  }
  await route.continue();
});
page.on('pageerror', error => errors.push(error.message));
page.on('console', message => { if (message.type() === 'error') console.log('Browser:', message.text().slice(0, 500)); });
context.on('request', request => {
  if (!['GET', 'HEAD', 'OPTIONS'].includes(request.method())) uploads.push(request.url());
});
await page.addInitScript(() => {
  const getUserMedia = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
  window.lingualTestTracks = [];
  navigator.mediaDevices.getUserMedia = async (...args) => {
    const stream = await getUserMedia(...args);
    window.lingualTestTracks.push(...stream.getTracks());
    return stream;
  };
});
try {
  await page.goto(targetURL);
  await page.getByRole('button', { name: 'New entry' }).click();
  await page.getByRole('button', { name: 'Enable voice', exact: true }).click();
  await page.getByRole('region', { name: 'Listening only', exact: true }).waitFor({ timeout: 180000 });
  let previousLength = 0;
  for (let cycle = 1; cycle <= 2; cycle++) {
    if (cycle === 2) {
      assert.ok(modelDownloads.some(url => url.endsWith('.onnx')), 'Cold start must download real model weights from this static site.');
      requireCachedModel = true;
      const priorRequests = modelDownloads.length;
      await page.reload();
      await page.getByRole('button', { name: 'Enable voice', exact: true }).click();
      await page.getByRole('region', { name: 'Listening only', exact: true }).waitFor({ timeout: 180000 });
      assert.equal(modelDownloads.length, priorRequests, 'Reload must reuse Cache Storage without requesting model files.');
    }
    await page.getByRole('button', { name: 'Resume entry', exact: true }).click();
    await page.getByRole('button', { name: 'Stop entry', exact: true }).waitFor({ timeout: 15000 });
    const started = Date.now();
    await page.getByLabel('Uncommitted speech').waitFor({ timeout: 5000 });
    const latency = Date.now() - started;
    const provisional = await page.getByLabel('Uncommitted speech').innerText();
    assert.ok(provisional.trim().length > 0, 'Real streaming words must appear before Stop.');
    assert.ok(latency < 3000, `First provisional words were too slow: ${latency} ms`);
    console.log(`Cycle ${cycle}: first gray words after ${latency} ms: ${provisional}`);
    await page.screenshot({ path: `.local/live-speech-cycle-${cycle}.png`, fullPage: true });
    await page.waitForTimeout(Math.max(0, 6500 - latency));
    await page.getByRole('button', { name: 'Stop listening', exact: true }).click();
    await page.getByRole('button', { name: 'Start listening', exact: true }).waitFor({ timeout: 60000 });
    const text = await page.locator('textarea[aria-label="Entry text"]').inputValue();
    assert.ok(text.length > previousLength, 'A restarted microphone must produce new text.');
    assert.match(text, /thoughts|speak freely|edit my words/i);
    previousLength = text.length;
    assert.ok(await page.locator('.has-audio').count() > 0, 'Speech must have word-level audio links.');
    assert.equal(await page.evaluate(() => window.lingualTestTracks.every(track => track.readyState === 'ended')), true, 'Stop must release all microphone tracks.');
    console.log(`Cycle ${cycle}: transcript and audio links present; microphone released.`);
    console.log(text);
  }
  assert.deepEqual(await page.getByRole('alert').allTextContents(), []);
  assert.deepEqual(errors, []);
  assert.deepEqual(uploads, []);
  assert.deepEqual(externalSpeechRequests, []);
  await page.getByRole('button', { name: 'Recordings', exact: false }).click();
  await page.screenshot({ path: '.local/speech-verification.png', fullPage: true });
  console.log('PASS: real Vosk provisional words + Whisper from static assets, cold load and cached reload, repeated capture, timed words, teardown, no external speech requests or uploads.');
} catch (error) {
  await page.screenshot({ path: '.local/speech-failure.png', fullPage: true });
  throw error;
} finally { await context.close(); }

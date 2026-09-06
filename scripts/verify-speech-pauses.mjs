/** Exercise real streaming + Whisper with deterministic pauses through an actual MediaStream. */
import { chromium } from '../web/node_modules/playwright-core/index.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync } from 'node:fs';
import assert from 'node:assert/strict';

mkdirSync('.local/logs', { recursive: true });
for (const [name, text] of [['first', 'Violet flowers grow in the garden.'], ['second', 'Another sentence begins here.'], ['command', 'Play note.']]) {
  execFileSync('say', ['-v', 'Samantha', '-o', `.local/${name}.aiff`, text]);
  execFileSync('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', `.local/${name}.aiff`, `.local/${name}.wav`]);
}
const fixtureInfo = JSON.parse(execFileSync('python3', ['-c', `
import wave, json
parts=[]
for name in ['first','second','command']:
    with wave.open('.local/'+name+'.wav','rb') as f: parts.append(f.readframes(f.getnframes()))
# Deliberate long pause must survive recording time even when capture flushes during it.
audio=parts[0]+bytes(16000*2*9)+parts[1]+bytes(16000*2*2)+parts[2]+bytes(16000*2*2)
with wave.open('.local/speech-pauses.wav','wb') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000); f.writeframes(audio)
print(json.dumps({'seconds':len(audio)/32000,'commandEnds':len(audio)/32000-2}))
`], { encoding: 'utf8' }));
const bytes = readFileSync('.local/speech-pauses.wav').subarray(44).toString('base64');
const origin = process.env.LINGUAL_TEST_URL || 'http://127.0.0.1:5174';
const browser = await chromium.launch({ headless: true, args: ['--autoplay-policy=no-user-gesture-required'] });
const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
await context.route('**/*', route => new URL(route.request().url()).origin === new URL(origin).origin ? route.continue() : route.abort());
await page.addInitScript(({ bytes }) => {
  const raw = Uint8Array.from(atob(bytes), character => character.charCodeAt(0));
  const data = new DataView(raw.buffer);
  const samples = Float32Array.from({ length: raw.length / 2 }, (_, index) => data.getInt16(index * 2, true) / 32768);
  navigator.mediaDevices.getUserMedia = async () => {
    const audio = new AudioContext({ sampleRate: 16000 });
    await audio.resume();
    const source = audio.createBufferSource();
    source.buffer = audio.createBuffer(1, samples.length, 16000);
    source.buffer.copyToChannel(samples, 0);
    const destination = audio.createMediaStreamDestination();
    source.connect(destination);
    window.lingualFixtureSource = source;
    window.lingualFixtureAudio = audio;
    return destination.stream;
  };
}, { bytes });
try {
  await page.goto(origin);
  await page.getByRole('button', { name: 'Enable voice', exact: true }).click();
  await page.getByRole('region', { name: 'Listening only', exact: true }).waitFor({ timeout: 180000 });
  await page.getByRole('button', { name: 'Resume entry', exact: true }).click();
  await page.getByRole('button', { name: 'Stop entry', exact: true }).waitFor({ timeout: 15000 });
  await page.getByRole('button', { name: 'Stop listening', exact: true }).waitFor({ timeout: 10000 });
  await page.evaluate(() => {
    window.lingualFixtureSource.start(window.lingualFixtureAudio.currentTime + 0.2);
    window.lingualFixtureStart = performance.now() + 200;
  });
  await page.getByLabel('Uncommitted speech').waitFor({ timeout: 4000 });
  const firstWordMs = await page.evaluate(() => performance.now() - window.lingualFixtureStart);
  assert.ok(firstWordMs < 3000, `First gray word took ${firstWordMs} ms`);
  await page.screenshot({ path: '.local/live-speech-inline.png', fullPage: true });
  await page.getByLabel('Voice action recognized').filter({ hasText: 'play entry' }).waitFor({ timeout: (fixtureInfo.seconds + 8) * 1000 });
  const commandDelayMs = await page.evaluate((end) => performance.now() - window.lingualFixtureStart - end * 1000, fixtureInfo.commandEnds);
  assert.ok(commandDelayMs < 3000, `Command recognition took ${commandDelayMs} ms after its audio ended`);
  await page.getByRole('button', { name: 'Stop listening', exact: true }).click();
  await page.getByRole('button', { name: 'Resume entry', exact: true }).waitFor({ timeout: 60000 });
  const text = await page.getByLabel('Entry text').inputValue();
  assert.match(text, /garden[.!]?\n\nAnother/i, 'The long pause must become a paragraph in the normal transcript.');
  assert.doesNotMatch(text, /play note/i, 'Recognized commands must not become entry prose.');
  const saved = await page.evaluate(async () => {
    const db = await new Promise((resolve, reject) => { const request = indexedDB.open('lingual-local', 1); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
    const read = store => new Promise((resolve, reject) => { const request = db.transaction(store).objectStore(store).getAll(); request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error); });
    const entries = await read('entries'); const clips = await read('clips');
    db.close();
    return { entry: entries[0], clips: clips.map(({ audio, ...clip }) => clip) };
  });
  const totalAudio = saved.clips.reduce((sum, clip) => sum + clip.duration, 0);
  const voicedDuration = saved.entry.spans.reduce((sum, span) => sum + span.sourceEnd - span.sourceStart, 0);
  assert.ok(totalAudio - voicedDuration > 8, 'Playback word ranges must exclude the deliberate long silence.');
  assert.ok(saved.entry.spans.every(span => span.sourceEnd > span.sourceStart));
  await page.screenshot({ path: '.local/live-speech-paragraph-command.png', fullPage: true });
  await page.getByRole('button', { name: 'Help', exact: true }).click();
  await page.getByLabel('Find a voice action').fill('export entry');
  await page.locator('.command-palette').getByRole('button', { name: 'export entry ↗', exact: true }).click();
  const downloading = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export audio', exact: true }).click();
  const download = await downloading;
  await download.saveAs('.local/speech-pauses-edited.wav');
  const exportedSeconds = (readFileSync('.local/speech-pauses-edited.wav').length - 44) / 32000;
  assert.ok(exportedSeconds > 1 && exportedSeconds <= voicedDuration + 0.01, 'The exported WAV must use the trimmed speech intervals.');
  assert.deepEqual(errors, []);
  console.log(JSON.stringify({ firstWordMs: Math.round(firstWordMs), commandDelayMs: Math.round(commandDelayMs), totalAudio, voicedDuration, exportedSeconds, text }, null, 2));
  console.log('PASS: real gray hypotheses, long-pause paragraph, audible word boundaries, and recognized play note without dictating the command.');
} catch (error) {
  await page.screenshot({ path: '.local/speech-pauses-failure.png', fullPage: true });
  console.log(await page.locator('body').innerText());
  throw error;
} finally { await browser.close(); }

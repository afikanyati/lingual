import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ensureAsset } from './prepare-speech-assets.mjs';

const bytes = Buffer.from('synthetic model bytes');
const file = { path: 'model.onnx', size: bytes.length, algorithm: 'sha256', digest: createHash('sha256').update(bytes).digest('hex') };
async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), 'lingual-assets-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  return join(directory, file.path);
}
test('downloads exact pinned bytes and reuses a verified local asset offline', async t => {
  const destination = await fixture(t);
  await ensureAsset(file, destination, 'https://example.test/pinned/model.onnx', async () => new Response(bytes));
  await ensureAsset(file, destination, 'https://example.test/pinned/model.onnx', async () => { throw new Error('Network must not be needed'); });
  assert.deepEqual(await readFile(destination), bytes);
});
test('repairs a corrupt cached file instead of deploying it', async t => {
  const destination = await fixture(t); await writeFile(destination, 'corrupt');
  await ensureAsset(file, destination, 'https://example.test/model.onnx', async () => new Response(bytes));
  assert.deepEqual(await readFile(destination), bytes);
});
test('rejects HTML fallback responses and leaves no deployable asset', async t => {
  const destination = await fixture(t);
  await assert.rejects(ensureAsset(file, destination, 'https://example.test/model.onnx', async () => new Response('<html>not a model</html>')), /integrity/);
  await assert.rejects(readFile(destination), { code: 'ENOENT' });
});
test('fails the build on HTTP download errors', async t => {
  const destination = await fixture(t);
  await assert.rejects(ensureAsset(file, destination, 'https://example.test/model.onnx', async () => new Response('', { status: 503 })), /503/);
});
test('verifies small Hugging Face files using their Git blob identity', async t => {
  const destination = await fixture(t);
  const digest = createHash('sha1').update(`blob ${bytes.length}\0`).update(bytes).digest('hex');
  await ensureAsset({ ...file, algorithm: 'git-sha1', digest }, destination, 'https://example.test/config.json', async () => new Response(bytes));
  assert.deepEqual(await readFile(destination), bytes);
});

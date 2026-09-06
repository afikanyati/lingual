import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, rename, rm, copyFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));

/** Verify pinned upstream identity, including Git's blob header for non-LFS files. */
function matchesAsset(bytes, file) {
  if (bytes.length !== file.size) return false;
  const hash = createHash(file.algorithm === 'git-sha1' ? 'sha1' : 'sha256');
  if (file.algorithm === 'git-sha1') hash.update(`blob ${bytes.length}\0`);
  return hash.update(bytes).digest('hex') === file.digest;
}

/** Reuse verified files; an interrupted, stale or HTML download must never become a deployed model. */
export async function ensureAsset(file, destination, url, fetchAsset = fetch) {
  try {
    if (matchesAsset(await readFile(destination), file)) return;
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  const response = await fetchAsset(url, { signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw new Error(`Speech asset download failed (${response.status}): ${file.path}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (!matchesAsset(bytes, file)) throw new Error(`Speech asset integrity check failed: ${file.path}`);
  await mkdir(dirname(destination), { recursive: true });
  const temporary = `${destination}.${process.pid}.partial`;
  try {
    await writeFile(temporary, bytes);
    await rename(temporary, destination);
  } finally {
    await rm(temporary, { force: true });
  }
}

/** Prepare a complete static distribution; no model API or CDN is needed by the deployed speech engine. */
export async function prepareSpeechAssets() {
  const manifest = JSON.parse(await readFile(resolve(repository, 'web/src/config/speech-assets.json'), 'utf8'));
  const transformers = resolve(repository, 'web/node_modules/@huggingface/transformers');
  const installed = JSON.parse(await readFile(resolve(transformers, 'package.json'), 'utf8'));
  if (installed.version !== manifest.transformersVersion) throw new Error('Update the speech asset manifest when upgrading Transformers.js.');
  const publicRoot = resolve(repository, 'web/public/speech');
  const modelRoot = resolve(publicRoot, manifest.revision, 'models', manifest.model);
  for (const file of manifest.files) {
    await ensureAsset(file, resolve(modelRoot, file.path), `https://huggingface.co/${manifest.model}/resolve/${manifest.revision}/${file.path}`);
  }
  const runtimeRoot = resolve(publicRoot, `runtime-${manifest.transformersVersion}`);
  await mkdir(runtimeRoot, { recursive: true });
  for (const name of ['ort-wasm-simd-threaded.jsep.mjs', 'ort-wasm-simd-threaded.jsep.wasm']) {
    await copyFile(resolve(transformers, 'dist', name), resolve(runtimeRoot, name));
  }
  // Keep the converted model card and Apache license with the redistributed files.
  await copyFile(resolve(transformers, 'LICENSE'), resolve(modelRoot, 'LICENSE-APACHE-2.0.txt'));
  await copyFile(resolve(repository, 'docs/licenses/whisper-MIT.txt'), resolve(modelRoot, 'LICENSE-WHISPER-MIT.txt'));
  await copyFile(resolve(repository, 'docs/licenses/onnxruntime-MIT.txt'), resolve(runtimeRoot, 'LICENSE.txt'));
  await prepareLiveSpeechAssets(publicRoot, transformers);
  console.log(`Static Whisper ready: ${(manifest.files.reduce((sum, file) => sum + file.size, 0) / 1e6).toFixed(1)} MB model + local WASM runtime. Revision ${manifest.revision}.`);
}

/** Pin both upstream ZIP and deterministic browser archive; keep the streaming engine on our static origin. */
async function prepareLiveSpeechAssets(publicRoot, transformers) {
  const root = resolve(publicRoot, 'vosk-0.0.3');
  const destination = resolve(root, 'models/en-us-0.15.tar.gz');
  const archive = { path: 'en-us-0.15.tar.gz', size: 41116398, algorithm: 'sha256', digest: 'a381a5554ac9942329307a921f6d76bcd4814e0f7330359aa10149b1a4181a11' };
  await mkdir(dirname(destination), { recursive: true });
  let valid = false;
  try { valid = matchesAsset(await readFile(destination), archive); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (!valid) {
    const zip = resolve(repository, '.local/vosk-model-small-en-us-0.15.zip');
    await ensureAsset({ path: 'vosk-model-small-en-us-0.15.zip', size: 41205931, algorithm: 'sha256', digest: '30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498' }, zip, 'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip');
    const temporary = `${destination}.partial`;
    execFileSync('python3', [resolve(repository, 'scripts/pack-vosk.py'), zip, temporary]);
    if (!matchesAsset(await readFile(temporary), archive)) throw new Error('Vosk browser archive integrity check failed.');
    await rename(temporary, destination);
  }
  const installedRoot = resolve(repository, 'web/node_modules/@lichess-org/vosk-browser');
  const installed = JSON.parse(await readFile(resolve(installedRoot, 'package.json'), 'utf8'));
  if (installed.version !== '0.0.3') throw new Error('Update streaming asset pins when upgrading Vosk.');
  for (const file of ['vosk.worker.js', 'vosk.wasm']) await copyFile(resolve(installedRoot, 'dist', file), resolve(root, file));
  await copyFile(resolve(transformers, 'LICENSE'), resolve(root, 'LICENSE-APACHE-2.0.txt'));
  console.log('Static Vosk ready: 41.1 MB model + 3.1 MB runtime; Apache-2.0.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await prepareSpeechAssets();

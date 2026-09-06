# Streaming speech on static hosting

Lingual uses Vosk small-en-us-0.15 for streaming hypotheses and voice actions, followed by the English Whisper tiny.en model on the visitor's device, inside a Web Worker using WebAssembly. Firebase Hosting serves the React app, model weights, and runtime as ordinary static files. It does not perform transcription. There is no inference server, Firebase Function, API key, or paid speech API.

## Build and use

```sh
yarn --cwd web install --frozen-lockfile
yarn build
yarn preview
```

Open the local preview and select **Enable voice** to load the models and start listening without saving speech to an entry. Choose **Start entry** to create a new entry and record, or **Resume entry** to record into the selected entry. The same build can be served over HTTPS by Firebase Hosting or another static host. Microphone access requires HTTPS (localhost is the development exception).

Both `yarn dev` and `yarn build` prepare the speech files automatically. On the first build, the preparation script downloads approximately 43 MB of model/config files from the pinned Hugging Face revision in `web/src/config/speech-assets.json`. It verifies each file's size and upstream content hash. Subsequent builds reuse verified files without downloading them again. The matching runtime comes from the installed, version-checked Transformers.js package. Interrupted downloads and HTML/error responses fail the build rather than becoming deployable models.

Everything needed for speech is included under `web/dist`. Generated downloads in `web/public/speech` are ignored by Git; a fresh checkout regenerates them. Preserve the complete `dist` directory when hosting, including `speech`, `assets`, and `capture-worklet.js`.

The live engine uses `@lichess-org/vosk-browser` 0.0.3. The build downloads the official 41.2 MB Vosk ZIP, verifies its SHA-256, and uses Python 3 to produce a deterministic tar.gz (also hash-checked). The 41.1 MB browser archive and 3.1 MB worker/WASM runtime are included under `speech/vosk-0.0.3/`, with the Apache-2.0 license. See the [official model list](https://alphacephei.com/vosk/models) and [browser runtime source](https://github.com/lichess-org/vosk-browser).

## Visitor downloads and cost

The pinned build contains 42,990,685 bytes of model/config files and approximately 21.6 MB of runtime files: about 64.6 MB for Whisper before HTTP compression. Vosk adds about 44.3 MB, making the combined speech download approximately 109 MB, plus the app. Actual transferred bytes depend on hosting compression. The model is cached in browser Cache Storage when available; revision-specific URLs prevent old model files mixing with new ones. Vosk caches its extracted model in IndexedDB; the runtime also receives normal HTTP caching. Browser eviction or clearing site data can require another download. The whole app is not an offline-installed PWA.

All speech assets come from the same origin as the deployed site. The worker disables remote model loading and explicitly overrides the library's default runtime CDN. Audio stays in the browser: Float32 samples go to its worker, and the worker returns text and word timings. Browser/device speed and memory determine performance. One inference thread avoids requiring cross-origin-isolation headers.

There is no per-transcription service bill. Ordinary static-hosting storage and download bandwidth still apply, especially for first-time visitors. The current model is English-only.

## Firebase Hosting

`firebase.json` serves `web/dist`, rebuilds before deployment, sets WASM/model content types, and applies long-lived caching to versioned speech files and hashed app assets. This single-page editor uses no client-side URL routes, so no catch-all rewrite is needed; missing model files should produce a real 404 rather than HTML.

Live URL: **https://lingual-notetaker.web.app**. Project: **lingual-web-app** (Lingual Note Taker), selected in `.firebaserc`, with Hosting target `app` pointing to `lingual-notetaker`. `yarn deploy:hosting` runs `yarn test:predeploy` and deploys Hosting explicitly to this project. Firebase Functions are not involved. The older `lingual-app` and `lingual-io` landing pages are separate and were not changed.

Deployment verification checked all 48 static files, WASM content types, the live HTML against the local build, real Vosk and Whisper transcription, model reuse after reload, microphone teardown, and absence of speech uploads. Localhost entries do not automatically appear on the hosted origin; move them using Settings backup and restore.

## Verification

- `yarn test:assets`: download integrity, corrupt-file repair, cached build reuse, HTTP failures and Git-blob verification.
- `yarn test:predeploy`: asset tests, web/native unit tests, production build, and browser workflows, including missing model errors.
- `yarn test:speech` with the preview running: fresh Chrome profile, all external hosts blocked, actual local Vosk and Whisper, gray hypothesis latency, synthetic microphone input, word timestamps, capture restart, and microphone release. The second harness uses an actual generated MediaStream with a nine-second pause and the spoken command “play note” to verify paragraph formatting and command acceptance. Reload then forbids all model HTTP requests to prove cached model reuse. It also rejects uploads and external speech requests.

Implementation follows the [Transformers.js local-model configuration](https://huggingface.co/docs/transformers.js/main/custom_usage) and [Firebase static-hosting headers](https://firebase.google.com/docs/hosting/full-config#headers). Redistribution preserves the model card, Apache-2.0 converted-model license, upstream Whisper MIT notice, and ONNX Runtime MIT notice.

## Recognition and audio timing

Microphone packets go immediately to Vosk. Gray text is an uncommitted hypothesis: it is neither editable nor persisted as entry prose. Capture closes an utterance after roughly 0.8 seconds of silence, or after 15 seconds of continuous input. A complete Vosk command receives an orange recognition indicator and runs once, in order after earlier commits. A partial command prefix never executes: “play note is what I said yesterday” remains prose. Whisper finalizes non-command text and punctuation while the gray buffer stays visible. Recognition is English-only and provisional words can change.

The Swift reference is `SpeechRecognitionEngine.didHypothesizeTranscription`, its early command recognition, and `Entry`'s buffer/commit separation. The web uses an utterance-end command barrier instead of executing a transient hypothesis after the native 0.3-second timer. This prevents prefix commands from swallowing ordinary speech.

Whisper word timestamps can contain silence. The app measures 10 ms audio frames, retains quiet speech relative to each interval's peak, preserves gaps shorter than 100 ms and keeps 30 ms of edge padding. Uncertain/all-silent estimates retain their source interval instead of deleting a word. Playback and WAV export share this trimming when silence omission is enabled; original recording blobs remain unchanged. Recorded-session time remains separate from playback duration, so a >7-second pause can generate a paragraph even though playback removes it. This is conservative energy-based trimming, not a claim that all noisy-room silence is perfectly detected.

# Lingual

A place to think out loud, then edit the words **and their recorded audio**. This repository contains the recovered Swift iOS app and a local React implementation.

## Run the React app

Requires Node.js 22+, Yarn Classic, Python 3 (first-build model packaging), and a browser with Web Audio and WebAssembly. Chrome is the browser used for verification.

```sh
yarn --cwd web install --frozen-lockfile
yarn dev
```

Open **http://127.0.0.1:5173**. For the built version:

```sh
yarn build
yarn preview
```

The built preview uses **http://127.0.0.1:5174**. Use one address consistently: browser storage belongs to the exact origin, including its port.

1. Click **Enable voice** to load the speech models and allow the microphone. Listening starts immediately in **Listening only**: recognized words appear separately, and neither text nor audio is saved to the selected entry. Transcript fields remain read-only.
2. Say or click **Start entry** to create a new entry and begin recording. **Resume entry** explicitly records into the selected entry. Gray provisional words appear while recording; Whisper finalizes them after a pause or in bounded chunks. **Stop entry** drains the final audio and returns to listening only. **Stop listening** turns the microphone off. Listening-only audio is discarded and never sent to Whisper; disabling voice actions does not turn this mode into dictation.
3. In **Audio-linked view**, tap a word to audition it, tap during playback to seek, or Shift-click a range. Selection actions support playback, copy/cut/paste, replacement, speed adjustment, and export. **Transcript** lets you select recorded words without typing. Partial-word edits operate on the whole recorded word.
4. **Voice actions** are on by default; an explicit off/on choice is remembered in this browser. Speak an action as its own utterance; an orange indicator confirms recognition (including “play note” as an alias for “play entry”); open **Help** for all 92 native actions and their buttons. Turn voice actions off to dictate a command phrase as entry content. Replacement candidates also come from speech.
5. Use **Settings → Back up entries and audio** to keep a portable copy of entries, history, and audio. Restoring adds entries instead of overwriting existing ones, and requires recordings for every word in the entry and its undo/redo history.

A compact guide below **Read it back** consistently introduces four everyday commands: **start entry**, **resume entry**, **play entry**, and **stop entry**. Selecting text or playing audio does not replace this guide with specialized commands. The guide appears after voice is enabled. **Start entry** creates and records a new entry; **resume entry** records into the selected entry. **Create entry** remains available in Help to create a blank entry without recording. While listening with voice actions enabled, matching whole-word prefixes appear inside the note: recognized words use orange with white text, and the remaining words are gray. Suggestions use the native vocabulary and aliases, account for selection/playback/replacement state, and never execute an unfinished utterance. They clear when the speech changes, a chunk finishes, listening stops, or voice actions are disabled. The guide priorities are web presentation choices; the Swift dictionary does not mark a favorites list.

Selecting text also shows **Play selection**, **Update selection**, **Copy selection**, **Delete selection**, and **Remove selection** in the note’s command-discovery area. These are clickable actions even with voice actions off; Remove clears the selection without editing it. Live spoken completions take priority in the same area. Suggestions disappear when the selection clears, a dialog or replacement opens, or automatic browsing owns the selection. Playback and copy are omitted for words without source audio.

Headphone-dependent audio follows the **detected system audio output** automatically. There is no headphone mode, checkbox, or confirmation button, and the retired saved flag is removed. Lingual rechecks devices on connection changes, after microphone permission, on returning to the tab, and every three seconds while visible. Recognized headphone output enables passive echo, spoken feedback, selection repeat, and Walk/Run audio; switching away cancels dependent audio. Enabled feature preferences still apply.

Detection is best effort: browsers expose device names, not a standardized headphone type or proof that headphones are being worn. Lingual recognizes clearly named default outputs (such as Headphones, Headset, or AirPods). A connected headset that is not the system output does not enable these features. Hidden, missing, or ambiguous output information leaves dependent audio paused and displays an explanation; there is no manual bypass. See the [browser device information API](https://developer.mozilla.org/en-US/docs/Web/API/MediaDeviceInfo). Physical wired/Bluetooth routing still needs device testing.

Ordinary recording and speaker playback remain available. Settings explains each option, including the distinction between **Punctuation** (speaking punctuation names during read-back) and **Punctuation suggestions** (displaying punctuation in the transcript); both default on, while saved off choices are respected.

**Recordings** expands the original audio list and flips its chevron to show the open state. Each passage has an orange playback progress line and an elapsed/total timer. Pause preserves its position; playing a completed passage starts again from the beginning. Switching entries or recordings clears the previous player.

Hover over a button or focus it with Tab for an explanation. **Play** uses your recorded voice; **Read it back** uses the local synthesized voice. Search uses **Find an entry**.

On phones and narrower tablets, the library opens from the book button in the top bar. Tap outside it or use Close to return to the entry. Controls rearrange into rows with larger touch targets, and Settings/Help scroll within the screen with their Close button kept visible. Desktop screens retain the sidebar. The responsive browser suite covers 320–1440px widths, phone landscape, recording controls, drawer keyboard behavior and resizing between layouts.

### Speech, privacy, and cost

The web app streams gray provisional words through **Vosk**, then finalizes prose and punctuation with quantized **Whisper tiny.en** through Transformers.js and ONNX Runtime Web. Both engines run in local Web Workers. Combined first-use speech assets are approximately **109 MB** before HTTP compression and are cached when available. It has no inference server, API key, account, paid speech API, or Firebase Functions dependency. Your microphone samples are passed to the worker, not sent to a speech service. The build downloads and integrity-checks a pinned model revision from Hugging Face, then packages it with the runtime. Visitors fetch all speech files from the deployed site itself. Models are cached where the browser permits it. First use needs a network connection, download space, and time to initialize.

The model is English-only, matching the original app's `en-US` recognizer. Accuracy and speed depend on speech and hardware. Read-back uses an installed **local** English system voice; install one in your OS if none appears. It does not fall back to a remote TTS service.

Entries and recordings use IndexedDB; preferences use localStorage. Clearing this site's browser data removes them. The project folder is safely outside iCloud, but browser data still needs backups. The local edition has no CloudKit/Firebase synchronization. The app is hosted at [lingual-notetaker.web.app](https://lingual-notetaker.web.app) from `web/dist`; normal hosting bandwidth/storage charges can still apply. Localhost and the hosted app have separate browser storage: use Settings → Back up entries and audio on localhost, then restore the backup on the hosted site to move your entries.

## Features and parity

- Entry library, search, creation, stopped-entry editing, confirmation before deletion, and local autosave.
- Microphone recording with a centered listening control and recording timer; retryable transcription with source audio saved first.
- Actual word timestamps, original recording playback, edited audio playback, and word highlighting.
- Selection of words/sentences/paragraphs/last commit; anchor/focus adjustment, expand/reduce, shift, copy/cut/delete/paste, and a cross-entry audio clipboard.
- Staged selection replacement with accept/redo/cancel; undo/redo restores text **and audio links**.
- Play/echo/walk/run for entries, selections, and commits; entry-list previews; pause/resume/seek and rate/volume controls.
- Live native YIN pitch detection and note/frequency display; stored word pitch follows original-audio playback and survives editing/backup. A 15-reading pitch baseline guides installed local voice selection.
- Punctuation, temporal spacing, capitalization, emphasis, silence, passive echo, and feedback preferences; local English lexical guards and recorded-word power/rate analysis.
- Original welcome entry and both recordings, loaded on demand from Help (31 MB); active entry and caret restored after reload.
- Text and edited WAV export, original recording downloads, and complete backup/restore.
- All **92 active Swift command identities**, 142 token aliases, and 191 grammar rules, generated from the native catalogue and checked by tests.

The [speech-only functionality review](docs/speech-only-review.md) records corrections to unintended web additions, including typed entries, typed replacement drafts, editable titles, arbitrary audio import, and synthesized fallback playback.

Punctuation suggestions can be turned off to hide sentence punctuation, including Whisper’s, without discarding the original transcript or audio. Turning the setting back on restores it.

See [punctuation and recorded-word behavior](docs/punctuation.md) for how Whisper punctuation and native pause suggestions work together.

See [the feature-by-feature parity report](docs/feature-parity.md) for implementation/test mapping and platform differences. The command count establishes coverage, not proof that every physical-device behavior is identical. Browser recording pauses when the tab becomes hidden; automatic background/lock-screen capture, system volume control, and Apple-specific haptics are platform differences. The native iPhone microphone/headset scenarios still require physical-device verification.

### Complete Swift source accounting

[The source review](docs/native-source-review.md) accounts for **all 125 Swift files and 36,092 lines**. [Its manifest](docs/native-source-audit.json) maps each function and every intervening line range to React/test files, a browser adaptation, native support code or an inactive experiment. Source hashes make changes invalidate the review. This is review coverage, not a claim that every line has a one-to-one JavaScript translation or a physical-device test.

`yarn test:source-audit` validates the inventory; it is included in `yarn test:predeploy`. Use `python3 scripts/native-source-audit.py --require-parity` to additionally reject explicitly recorded gaps. The browser adaptations and acceptance limits in the parity report still apply when that command passes.

## Swift app

Open `diction-processor.xcodeproj` and select the shared **lingual** scheme. The recovered target uses Swift 5 and iOS 15+. It builds with Xcode 26.2 without CocoaPods. For a physical iPhone, select your signing team/profile in Xcode.

```sh
yarn build:ios      # Ad hoc signed simulator build
yarn test:ios       # Simulator integration tests; defaults to iPhone 17 Pro
```

Override the simulator with `LINGUAL_IOS_DESTINATION='platform=iOS Simulator,name=YOUR SIMULATOR' yarn test:ios`. Simulator signing is deliberately enabled because the existing CloudKit entitlement is needed at launch.

[Recovery details](docs/recovery.md) identify the original folders and revisions. The local source was one commit newer than GitHub, and its uncommitted changes were preserved. [Bug audit](docs/bugs.md) explains the native speech repairs and remaining device checks.

## Verification

```sh
yarn test             # Web unit tests and portable native lifecycle tests
yarn --cwd web playwright install chromium --only-shell  # Once, for the pinned test browser
yarn test:e2e         # Chromium browser workflows
yarn test:predeploy   # Unit tests, production build, and browser suite; does not deploy
yarn test:ios         # Signed iOS simulator tests
```

The actual model/microphone check is separate so the regular suite does not require a large external model download:

```sh
yarn build
yarn preview          # Keep running in a separate terminal
yarn test:speech
```

`test:speech` starts a fresh Chrome profile with external hosts blocked, feeds synthetic speech through its microphone API twice, and runs the real model from the built static files. It checks new transcripts and word links, microphone release, and no uploads. Between cycles it reloads and blocks model HTTP requests to verify Cache Storage reuse. It never uses your real microphone. On macOS it creates the fixture with `say`/`afconvert`; on other systems provide `SPEECH_FIXTURE=/absolute/path/16khz-mono.wav`. Set `LINGUAL_TEST_URL` to use another local preview address. Logs and screenshots live in ignored `.local/`.

## Code map

- `diction-processor/`: original native app and focused reliability repairs.
- `native/`: reusable recognition-lifecycle state machine and its portable XCTest suite.
- `web/src/lib/`: immutable editing, audio timelines, command grammar, persistence, presentation, and backups.
- `web/src/speech/`: microphone lifecycle, inference worker, and request ownership.
- `web/src/interfaces/` and `web/src/enums/`: shared declarations.
- `web/tests/`: browser workflows.
- `scripts/convert-native-welcome.py`: rebuild the optional welcome bundle from the original archive/CAF recordings (requires ffmpeg).
- `scripts/native-source-audit.py`: validate source inventory, hashes, line accounting and review targets.
- `scripts/extract-command-catalog.py`: regenerate web command identities/aliases after changing Swift commands.

Original Swift source and sounds retain their existing ownership. See [third-party notices](docs/third-party.md) for the speech model and web dependencies.

## Branding

The web app uses the original Lingual wordmark and app icon, with navy, purple, plum, and orange selection highlights from the original designs. Assets are copied into this repository rather than referenced through iCloud. See [branding sources and colors](docs/branding.md).

### Original test-note coverage

[The test-note audit](docs/test-specifications.md) accounts for every one of the 184 items in **Lingual Tests to Specify:**, including its grouped cases and refactoring reminders. Each row links to automated tests or explains the remaining device check, browser adaptation, or feature gap. These inventory counts are separate from passing-test counts. The source review restored live/playback pitch, final-word looping, seek-by-word, sentence/paragraph navigation and generated-boundary capitalization. The report distinguishes automated contracts from remaining physical-device, local-voice and visual acceptance checks.

The new suites exercise cursor placement, all five speed-overlap shapes in both directions, audio-preserving clipboard operations, staged replacements, undo/redo, contextual commands, playback clocks, worker cancellation/retry, native notification queue behavior, and native transformation persistence. Browser speech fixtures exercise real React command dispatch, capture draining, and IndexedDB with synthetic audio and a deterministic model worker. They do not measure Whisper accuracy or replace physical headset checks.

`yarn test:specifications` validates the checklist and test links; `yarn test:predeploy` includes it. Update `docs/test-specifications.json`, then run `node scripts/test-specifications.mjs --write` to regenerate the report.

## Static Whisper deployment

Whisper is bundled for static hosting: no inference server or paid speech API is required. `yarn build` prepares verified model files and the matching runtime automatically. `firebase.json` points to the complete `web/dist` output and sets caching/content types for speech assets. The Firebase project is `lingual-web-app`, configured in `.firebaserc`, with Hosting target `app` pointing to `lingual-notetaker`. Deploy with `yarn deploy:hosting`, which runs the predeployment checks before publishing Hosting only. See [how static-hosted speech works](docs/static-speech.md) for download sizes, caching, Firebase setup, and the real-model regression test.

### Security

See the [security audit](docs/security-audit.md) for verified findings, local fixes, native CloudKit concerns and release checks. The app uses browser-local storage; it does not encrypt entries or authenticate speakers. Backups contain readable text and audio. `yarn test:predeploy` includes security regressions; `yarn --cwd web audit` checks current dependency advisories. Browser tests require a fresh preview server; set `LINGUAL_E2E_PORT` if port 5175 is occupied.

# Speech behavior verification — September 5, 2026

The current local build restores provisional gray text, visible voice-command recognition, waveform-based silence omission, and pause formatting in the ordinary Transcript view. This verifies those behaviors; the full native parity inventory still contains other gaps.

- `yarn test:predeploy`: 302 web unit tests, 39 Chrome browser tests, 5 asset-integrity tests, 4 portable Swift lifecycle tests, and the production build passed. Evidence: `.local/logs/live-predeploy-final.log`.
- `yarn test:speech`: real Vosk + Whisper with external speech requests blocked, cold load/cached reload, two microphone cycles and microphone release. First gray words appeared after 1,287 and 1,284 ms on this Mac. Evidence: `.local/logs/live-real-final.log`.
- The real MediaStream fixture produced its first provisional word after 1,088 ms. A nine-second pause generated a paragraph in the regular transcript. “Play note” produced the visible “play entry” acknowledgement 996 ms after its audio ended and did not become entry prose. The captured fixture was 16.90 seconds; its edited WAV was 3.42 seconds with silence omission enabled. Word intervals and original blobs remain available separately.
- Screenshots: `.local/live-speech-inline.png`, `.local/live-speech-paragraph-command.png`. Edited fixture: `.local/speech-pauses-edited.wav`.
- The browser preview at port 5174 was refreshed with the user's saved entry intact; both local models are prepared and the microphone is off.

These are synthetic English speech fixtures on desktop Chrome. Whisper misrecognized some words in the second fixture sentence; this work does not establish perfect transcription accuracy. Noisy-room trimming is conservative, and mobile performance/native hardware behavior still require separate checks. The [184-item inventory](test-specifications.md) remains explicit about remaining gaps. No Firebase deployment or commit was performed.

---

# Verification — September 4, 2026

Environment: macOS, Node 22.22.2, Yarn 1.22.22, installed Google Chrome, Xcode 26.2; iPhone 17 Pro simulator.

| Check | Result | Evidence |
| --- | --- | --- |
| `yarn test:predeploy` | PASS: 132 web unit tests, 4 portable native lifecycle tests, production build, 6 Chrome browser tests | `.local/logs/predeploy-final.log` |
| `yarn test:ios` | PASS: 3 app-hosted simulator tests, signed app launched | `.local/logs/ios-tests.log` |
| Generic iPhone Release build | PASS: arm64 iPhone compilation, signing disabled for this build | `.local/logs/ios-device-build.log` |
| `yarn test:speech` against built preview | PASS: real Whisper, two microphone start/stop cycles, new text and timed words, all microphone tracks ended, no page errors, no outgoing audio uploads | `.local/logs/speech-final.log`, `.local/speech-verification.png` |
| Built app desktop/mobile inspection | Captured at 1440px and 390px; mobile document fits its viewport | `.local/desktop-final.png`, `.local/mobile-final.png` |
| `git diff --check` | PASS | Working changes remain uncommitted |

The microphone fixture was generated with macOS speech synthesis and fed through Chrome's fake microphone device. The test checks the real capture/resampling/inference path without using a person's microphone. Both cycles produced the fixture's words and retained their audio. The automated headless environment exercised the compatibility capture fallback after an AudioWorklet startup timeout; unit tests also execute the shipped worklet at 16, 44.1, and 48 kHz and verify its final flush.

Browser tests run against a production preview, so Vite dependency-optimization reloads cannot interrupt speech-engine startup. Download-failure tests deliberately return HTTP 503 from the model host and verify a visible retryable error.

Focused red/green regressions captured the reversed playback aliases, wrong selection-rate alias, dropped final compatibility buffer, pause-based formatting across chunks, and word highlighting when original pauses are retained. Core editing tests cover undo to an empty entry, source timing after text edits, cross-entry copy/paste, deletion with shared audio references, replacement acceptance/cancellation, and backup validation.

Physical native mic/headset routing, real interruptions, long recordings, audible TTS/earcon quality and mobile Safari performance have not been validated by these automated results. The iPhone Release output is not an installed/signed distribution build. This report does not imply physical-device acceptance or Firebase deployment.

# Native parity verification — September 5, 2026

The [source review](native-source-review.md) accounts for 125 Swift files and 36,092 lines, including comments, blank lines, native scaffolding and inactive experiments. Its [manifest](native-source-audit.json) records contiguous source ranges, source hashes, implementation/test targets and explicit adaptation decisions. No source range remains unreviewed or classified as a known implementation gap. This is review accounting, not line execution coverage or proof of identical hardware behavior.

## Changes exercised

- Native YIN pitch detection, valid voice range and silence rejection; note/frequency display during listening and original-audio playback; stored pitch, power and speaking-rate metadata retained through edits and backups; speaker pitch baseline used for installed local voice selection.
- Word/sentence/paragraph selection scale, native paste-after-anchor behavior, headphone selection loops, idle word audition and active/paused word seeking.
- Native walk/run cadence, final-word looping, entry-list previews, cancellation of stale timers, and restoration after temporary playback or Echo.
- Dictation/command microphone ownership across selection, replacement, paused playback, Resume and completion; modal choices reject unrelated commands.
- Native lexical punctuation guards and adjective commas, generated-boundary capitalization, temporal spacing and queued sentence/paragraph feedback before passive Echo. Whisper punctuation remains stored and can be hidden by the suggestions preference.
- Original feedback sounds and headphone ambience; original welcome archive and recordings loaded atomically on demand; active entry/caret restoration; long-entry presentation and gray-buffer scrolling.

## Completed checks

`yarn test:predeploy` exited successfully:

| Check | Result |
| --- | --- |
| Swift source inventory/hash/range audit | 125 files; zero unreviewed ranges |
| Original test-note inventory | All 184 items accounted for; inventory counts are not passing tests |
| Static speech asset checks | 5 passed |
| Web unit tests | 355 passed across 28 files |
| Portable Swift lifecycle tests | 4 passed |
| TypeScript and production build | Passed |
| Browser workflows | 49 passed; version-matched Chromium |

`python3 scripts/native-source-audit.py --require-parity` also passed. `git diff --check` reported no whitespace errors. No test was skipped or marked expected-failure to achieve these results.

`yarn test:speech` passed separately against installed Google Chrome with the real Vosk and Whisper engines, synthetic microphone audio and external speech requests blocked. Cold/cached cycles displayed their first gray words after 1,285/1,287 ms and released the microphone after Stop. The pause/command fixture recognized “play note” after 1,036 ms, produced a paragraph at the long pause, and exported 3.390 seconds from 16.555 seconds of captured audio with silence omission enabled. These measurements describe this Mac and these fixtures; they do not guarantee latency or transcription accuracy for other speakers or devices.

The earlier installed-Chrome browser suite completed its assertions but hung in Playwright's browser-close response after Chrome exited. The regular suite now uses Playwright's pinned Chromium revision, limits workers to two, and has a global timeout. Install its browser once with `yarn --cwd web playwright install chromium --only-shell`. The installed-Chrome real-engine harness remains separate.

## Acceptance limits

The [184-item note audit](test-specifications.md) retains 17 partial-coverage items and 7 device checks. Physical microphone/headset behavior, audible local-voice mixing and exact native visual comparisons remain unverified. Browser background capture, best-effort default-output headphone detection, local voice availability and local storage replace iOS-specific services as described in the [parity report](feature-parity.md). The source accounting must not be described as unrestricted native hardware parity.

The local preview was refreshed. No commit, push or deployment was performed.

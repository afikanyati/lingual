# Native → React feature parity

Baseline: the recovered April 22, 2021 native application (`07f6e46`), including the preserved local edits and the reliability fixes documented in [bugs.md](bugs.md). The review now covers every one of the 125 Swift files, including Beethoven/Pitchy, UI controllers, data structures, extensions, tests and inactive experiments. See the [36,092-line source accounting](native-source-review.md) and its hashed manifest.

The React app dispatches every active native command. Review and command counts alone are not proof of equivalent behavior: [all 184 original test-note items](test-specifications.md) distinguish automated contracts from partial coverage, deliberate browser adaptations and physical-device checks. The source review records a decision for every line; hardware recognition and OS voice behavior still require acceptance on the target devices.

See [the speech-only review](speech-only-review.md) for native evidence and the removal of unintended keyboard entry, typed replacements, editable titles, audio import, extra dictation shortcuts, and fallback TTS playback. Search fields remain editable because their queries do not become entry content.

## Behavior coverage

| Native capability | React implementation | Verification |
| --- | --- | --- |
| Start, pause, stop, resume, edit an entry | Microphone lifecycle + serial inference queue; resumes the existing entry | Capture cancellation/final-buffer tests; two real Chrome microphone cycles with Whisper |
| Persist entries, dates, text and audio | IndexedDB autosave, list/search, date-derived titles, original clip storage | Storage unit tests; reload/search browser workflow |
| Live speech preview | Local Vosk streams gray hypotheses at the insertion point; Whisper commits final prose after a pause; recognized commands receive a separate indicator | Unit and browser buffer/command regressions; real-engine latency and pause harnesses |
| Keep text aligned to sound | Read-only transcript and speech-only replacements; every new word requires Whisper timestamps and source audio | Timeline tests; browser fixture with real WAV data |
| Select word/sentence/paragraph, entry/commit ranges | Audio-linked word buttons, Shift-click range, selection actions and commands | Selection boundary/state tests; browser editing workflow |
| Move selection / anchor / focus; expand/reduce/remove | Word/sentence/paragraph scale; selecting pauses dictation into command listening, clearing restores it, and replacement deliberately acquires dictation | Command state tests |
| Copy/cut/delete/paste text and sound | One clipboard containing text and source-audio references, including cross-entry paste | Timeline/storage tests and browser clipboard/audio-export workflow |
| Inspect clipboard | Play the clipboard's recorded source slices; reject incomplete audio | Command/effect implementation and shared playback path |
| Replace selection with speech | Staged replacement; record candidate, accept/redo/cancel | Command tests and browser accept/undo workflow |
| Undo/redo, including the empty entry | Snapshots include text, selection, source links and last commit; source clips retained | Empty-entry, deletion, audio-link and rate regression tests |
| Play entry/selection/commit | Edited slice order; retain or omit pauses; word highlights | Timeline tests; browser playback/export test |
| Pause/resume/stop/skip playback | Scheduled Web Audio timeline, ±10-second seeks, active/paused word-tap seeking and brief idle audition, original-recording playback | Shared player implementation and browser playback path |
| Echo entry/selection/commit | Installed local English system TTS with boundary highlights, pause/resume/stop and rate controls | Command mapping; requires an installed local voice for audible manual check |
| Passive echo while dictating | Queued local read-back when the default output is identified as headphones | Implemented; headset/feedback behavior needs physical listening checks |
| Walk and run words | Native clock cadence; headphone original-audio/echo comparison; Run ends by walking its final word; temporary playback/echo restores the interrupted walk | Command/state tests; shared original-audio playback path |
| Walk/run the entry list | Ten-second entry preview window, including short/empty entries | Implemented timer/ownership path; stepping state tested |
| Selection playback rate | Per-source-slice speed edit with undo | Timeline rate test; exported renderer uses same slice rate |
| Playback/echo rate and volume | App-level controls and voice actions | Preference persistence browser test; command transitions |
| Punctuation, silence, temporal and formatting suggestions | Model punctuation; pause-derived comma/sentence/paragraph breaks; temporal spacing; measured emphasis; non-destructive presentation | [Punctuation alignment tests](punctuation.md), prosody/pause tests and resampler tests |
| Pitch, speaking rate, power and duration | Native YIN detector, silence rejection, musical note/frequency while listening and playing, 15-sample speaker baseline for local voice selection; pitch/power/rate retained with recorded words | YIN signal/noise/range unit tests; real PCM browser pitch/playback/seek tests; backup metadata tests |
| Export text and edited audio | Entry/selection text and WAV; original recordings downloadable separately | Browser downloads and timeline tests |
| Action dictionary and contextual grammar | All 92 buttons and canonical phrases, original token aliases; selection/walk/entry shorthand | Catalogue equality test, per-command resolution/execution tests, browser dictionary test |
| Command feedback | Original earcons; queued sentence/paragraph notices before passive echo; headphone processing/modal/nature loops; spoken dialog choices | Queue/pause tests, cue request and modal workflow tests; audible headset mixing remains manual |
| Original welcome and session | On-demand welcome archive conversion, both original recordings, active entry/caret restoration | Atomic/idempotent import and long-entry rendering tests; browser playback and reload |
| Permission/error handling | Explicit activation, denial/retry, model download failure, disconnected/paused mic, bounded inference backlog | Unit permission/cancellation tests; browser model failure test |
| Recovery and portability | Audio stored before inference; retry failed clips; full validated backup and additive restore | Backup tests; storage reference-retention tests |

## Deliberate browser adaptations and limits

- **Background and lock-screen operation:** capture pauses and drains when the tab becomes hidden. Browsers do not provide the native iOS background-audio contract. Stay in the foreground while recording.
- **Microphone activation:** first activation is an explicit click and browser permission. With headphones, voice actions can continue during playback once enabled; loudspeaker playback releases capture until paused or finished, but the page cannot silently start a microphone before permission/user activation.
- **Speech engine:** the local English Whisper model replaces Apple's recognizer. Words, recognition accuracy, latency, and timestamp granularity can differ. Local Vosk supplies provisional words while Whisper commits at chunk boundaries.
- **Volume and feedback:** volume commands change Lingual's output; they do not move the device's system volume slider. Browser vibration is optional and does not reproduce Core Haptics patterns. Local TTS voices depend on the OS.
- **Headphone routing:** the native app handles audio-session route changes; the web app safely ends a disconnected capture and offers restart. There is no Headphones preference. Browser device enumeration and device-change events drive best-effort recognition of a clearly named default headphone output. Missing, hidden, or ambiguous names keep dependent audio off; connecting an unused headset does not change the default route. Passive echo and repeat audio are cancelled on loss of detection. Browser tests simulate connection, disconnection, permission visibility, and unknown outputs; physical routing is still unverified.
- **Storage and synchronization:** this requested local edition uses IndexedDB and portable backups. It does not connect to the original CloudKit container, read existing private iPhone entries, or synchronize across devices. No Firebase services were configured or deployed.
- **Command recognition:** voice actions are on by default. Commands must occupy an utterance; a sentence that happens to mention “delete entry” stays dictation. Turn voice actions off to dictate a command phrase. This keeps the full action vocabulary while avoiding accidental edits.
- **Resource limits:** capture pauses if eight chunks await inference. The captured audio is retained. Browser storage is origin-specific and can be cleared/evicted, so use backups.

These adaptations mean unrestricted native hardware/background parity cannot be claimed for a browser. The test-note audit separates automated contracts from narrower coverage and remaining acceptance checks. Physical mic/headset tests and audible echo review remain separate from automated proof.

Additional browser adaptations: the welcome audio downloads only when requested; repeated command replies are deduplicated by utterance ID rather than a one-second cooldown; deletion drains capture before confirmation; local English POS tagging replaces Apple NLTagger and can classify words differently. Browser controls group the same actions instead of copying UIKit layout. Native unused pan/repeat/tap helpers and NLP/transpose experiments are identified as inactive or support code in the source manifest.

## Notes and future ideas

The source notes are **Lingual - Master Product Document:**, **Lingual 2.0:**, and **Lingual Tests to Specify:** in **Verascope Design**. The listening/selection/route/quiet-speech bugs informed this repair. The notes also brainstorm a custom system keyboard, AR, sheet music, metronome, ambient effects and sample libraries. Those were not implemented native features and are not represented as completed features of this port.

## Complete native action inventory

Generated identities are in `web/src/enums/command.ts`; aliases and token rules are in `web/src/lib/native-commands.json`. Run `python3 scripts/extract-command-catalog.py` after changing the Swift catalogue. TypeScript's exhaustive switch prevents silently unhandled commands, and the test compares the enum directly against Swift source. Per-command smoke tests verify resolution and execution; the behavioral tests above supply stronger evidence for the core editing paths.

| Native identity | Canonical utterance |
| --- | --- |
| `PLAY_ENTRY` | play entry |
| `PAUSE_ENTRY` | pause entry |
| `CREATE_ENTRY` | create entry |
| `START_ENTRY` | start entry |
| `STOP_ENTRY` | stop entry |
| `RESUME_ENTRY` | resume entry |
| `DELETE_ENTRY` | delete entry |
| `ECHO_ENTRY` | echo entry |
| `RUN_ENTRY` | run entry |
| `WALK_ENTRY` | walk entry |
| `EDIT_ENTRY` | edit entry |
| `EXPORT_ENTRY` | export entry |
| `ENTER_ENTRY` | enter entry |
| `WALK_ENTRY_LIST` | walk entry list |
| `RUN_ENTRY_LIST` | run entry list |
| `ENTER_ENTRY_LIST` | enter entry list |
| `PLAY_ECHO` | play echo |
| `START_ECHO` | start echo |
| `PAUSE_ECHO` | pause echo |
| `STOP_ECHO` | stop echo |
| `RESUME_ECHO` | resume echo |
| `PAUSE_PLAYBACK` | pause playback |
| `RESUME_PLAYBACK` | resume playback |
| `STOP_PLAYBACK` | stop playback |
| `SKIP_PLAYBACK_BACKWARD` | skip playback backward |
| `SKIP_PLAYBACK_FORWARD` | skip playback forward |
| `ACTIVATE_PUNCTUATION` | activate punctuation |
| `DEACTIVATE_PUNCTUATION` | deactivate punctuation |
| `ACTIVATE_SILENCES` | activate silences |
| `DEACTIVATE_SILENCES` | deactivate silences |
| `ACTIVATE_TEMPORAL_SUGGESTIONS` | activate temporal suggestions |
| `DEACTIVATE_TEMPORAL_SUGGESTIONS` | deactivate temporal suggestions |
| `ACTIVATE_PUNCTUATION_SUGGESTIONS` | activate punctuation suggestions |
| `DEACTIVATE_PUNCTUATION_SUGGESTIONS` | deactivate punctuation suggestions |
| `ACTIVATE_FORMATTING_SUGGESTIONS` | activate formatting suggestions |
| `DEACTIVATE_FORMATTING_SUGGESTIONS` | deactivate formatting suggestions |
| `ACTIVATE_PASSIVE_ECHO` | activate passive echo |
| `DEACTIVATE_PASSIVE_ECHO` | deactivate passive echo |
| `INCREASE_VOLUME` | increase volume |
| `DECREASE_VOLUME` | decrease volume |
| `INCREASE_ECHO_RATE` | increase echo rate |
| `DECREASE_ECHO_RATE` | decrease echo rate |
| `INCREASE_PLAYBACK_RATE` | increase playback rate |
| `DECREASE_PLAYBACK_RATE` | decrease playback rate |
| `DELETE_SELECTION` | delete selection |
| `UPDATE_SELECTION` | update selection |
| `COPY_SELECTION` | copy selection |
| `CUT_SELECTION` | cut selection |
| `EXPORT_SELECTION` | export selection |
| `RUN_SELECTION` | run selection |
| `WALK_SELECTION` | walk selection |
| `ENTER_SELECTION` | enter selection |
| `REMOVE_SELECTION` | remove selection |
| `EXPAND_SELECTION` | expand selection |
| `REDUCE_SELECTION` | reduce selection |
| `PLAY_SELECTION` | play selection |
| `ECHO_SELECTION` | echo selection |
| `PAUSE_RUN` | pause run |
| `EXIT_WALK` | exit walk |
| `SHIFT_ANCHOR_RIGHT` | shift anchor right |
| `SHIFT_ANCHOR_LEFT` | shift anchor left |
| `SHIFT_FOCUS_RIGHT` | shift focus right |
| `SHIFT_FOCUS_LEFT` | shift focus left |
| `SHIFT_SELECTION_FORWARD` | shift selection forward |
| `SHIFT_SELECTION_BACKWARD` | shift selection backward |
| `SHIFT_NEXT_WALK_ELEMENT` | shift next walk element |
| `SHIFT_PREVIOUS_WALK_ELEMENT` | shift previous walk element |
| `SELECT_WORD` | select word |
| `SELECT_SENTENCE` | select sentence |
| `SELECT_PARAGRAPH` | select paragraph |
| `ACCEPT_SELECTION_UPDATE` | accept selection update |
| `REDO_SELECTION_UPDATE` | redo selection update |
| `CANCEL_SELECTION_UPDATE` | cancel selection update |
| `INCREASE_SELECTION_RATE` | increase selection rate |
| `DECREASE_SELECTION_RATE` | decrease selection rate |
| `PLAY_COMMIT` | play commit |
| `ECHO_COMMIT` | echo commit |
| `SELECT_COMMIT` | select commit |
| `ROLLBACK_COMMIT` | rollback commit |
| `WALK_COMMIT` | walk commit |
| `RUN_COMMIT` | run commit |
| `INSPECT_CLIPBOARD` | inspect clipboard |
| `PASTE_CLIPBOARD` | paste clipboard |
| `ENTER_DICTIONARY` | enter dictionary |
| `EXIT_DICTIONARY` | exit dictionary |
| `EXPORT_AUDIO` | export audio |
| `EXPORT_TEXT` | export text |
| `UNDO_CHANGE` | undo change |
| `REDO_CHANGE` | redo change |
| `GRANT_PERMISSION` | grant permission |
| `CANCEL_DIALOG` | cancel dialog |
| `CONTINUE_DIALOG` | continue dialog |

# Reliability and bug audit

## Swift changes

- **Invalid input bus:** `SPEECH_RECOGNITION_BUS` was 1. AVAudioInputNode supplies the microphone on output bus 0. The iOS integration test now checks that the configured bus exists on the actual input node.
- **Obsolete recognition callbacks:** an old task could finish after a new task began and alter the new task's flags or run its handlers. Recognition ownership is now explicit and old callbacks are ignored.
- **Pause/stop could hang:** transitions depended on an Apple completion callback arriving. Final results are allowed to drain, with a two-second fallback that completes pending transitions once.
- **Mutable request captured by the audio tap:** buffers could be appended to a replacement request. Each tap now owns the request created for its session.
- **Thread races:** UI and entry notifications ran from the real-time audio callback. Audio is copied before crossing to the main queue; recognizer callbacks and state transitions use the main queue. Already-captured buffers can still drain during finish so Stop does not truncate the saved audio tail.
- **Failed starts leaked resources:** tap installation and microphone startup now have rollback paths and visible retry messages. Invalid microphone formats are rejected before tap installation.
- **Headphone changes:** plugging and unplugging now use the same stop/drain/restart path, including when a selection exists.
- **Interruptions:** interruption begin pauses capture; `.shouldResume` restores the previous listening mode.
- **Quiet/short dictation:** removed the two-second new-session exclusion and the loudness gate on dictation. Those could reject text Apple had successfully recognized.
- **Startup deadlock:** microphone telemetry used to instantiate a second AVAudioEngine input graph. It now reads the audio session's native sample rate.
- **Late power lookup:** missing recording metadata or an empty power stream now yields a safe fallback instead of indexing an empty array or force-unwrapping a missing entry.
- **Reversed commands:** corrected next/previous playback direction and the “adjust up selection rate” alias, which had changed global playback speed. The generated web grammar receives the same repair.
- **Incorrect action labels:** selecting a sentence/paragraph was labelled `delete sentence` / `delete paragraph`. Corrected, with an iOS regression test.

The original four uncommitted local edits remain included. Simulator signing must be enabled (ad hoc signing is sufficient) to retain CloudKit entitlements at launch. A successful unsigned compilation alone is insufficient runtime proof.

## Web changes and regression targets

The web rewrite preserves original audio and edits a separate sequence of source slices. Text and audio links are part of the same undo snapshot. Copied speech retains its source times across entries. Entry and replacement transcripts are read-only. New words must have source-audio intervals; clipboard, undo/redo, and backup restore reject unrecorded words. Existing legacy data remains recoverable and missing audio is labelled. See [the speech-only review](speech-only-review.md).

Capture ownership includes pending permission requests, cancellation, device disconnection, backgrounding, final partial chunks, and a bounded inference queue. Audio is saved before inference. Failed transcription can be retried from Recordings; it does not discard the source clip. Commands match full utterances; turn voice actions off to dictate a command phrase. Entry deletion requires confirmation.

The browser suite covers persistence, clipboard, undo/redo, selection replacement, command discovery, preferences, audio export, responsive layout, and visible model-download failure. The separate live microphone check uses a synthetic audio fixture through Chrome's microphone interface and the real Whisper model.

## Physical-device verification still required

Exercise the native app with the built-in mic, wired headphones, and Bluetooth headphones; remove/reconnect each while recording and while selecting text. Verify short utterances immediately after Start, quiet dictation, selection removal, interruption/resume, and lock-screen recording. The simulator cannot establish real Bluetooth or physical microphone reliability.

## Regressions exposed by the original test-note suite

- Replacing a selected word with identical text and a new recording appended duplicate audio and could not be undone. Audio replacement now snapshots and replaces source spans even when the characters are unchanged.
- Pasting an empty clipboard could remove the current selection; it now leaves the entry and history untouched.
- Replacement during walk/run did not pause its moving target; it now stops playback and freezes the draft range.
- Walk-next could advance beyond the passage; it now remains bounded. Exit collapses selection at its end so subsequent dictation does not replace the last walked word.
- Bare halt/freeze paused recording instead of an active run; contextual parsing now targets browsing. Bare stop outside a mode is ignored as a command, as the note specifies. Use the explicit Stop entry command to stop dictation.
- Spoken Replace selection had no alias; it now opens the same staged editor as Update selection. Literal/ordinary sentences remain dictation.
- Entering an entry from list browsing left its loop active; opening or selecting an entry clears browsing and playback.
- Finished timeline playback retained the master audio gain connection and prepared buffers; completion now releases them.
- Native indefinite notifications omitted their `item` payload, crashing the observing UI. They now send the item.
- Clearing an active native notification queue left its exhaustion flag set and violated its invariant. Clearing now resets that flag before validation.

Regression evidence is in the linked suites in [the test-note audit](test-specifications.md). That audit also records unresolved behaviors; these repairs do not close all historical feature requests.

## September 5: missing speech behaviors in the React port

- Capture only fed complete chunks to Whisper, so no provisional speech or command-prefix feedback appeared. Vosk now receives live packets and renders a separate gray buffer at the insertion point; Whisper finalizes prose.
- Spoken commands waited for Whisper. Complete streaming commands now show an orange acknowledgement and execute once in queue order. The acknowledgement survives the automatic switch to command listening after playback starts. “Play note” is accepted as an alias for “play entry.”
- Playback treated Whisper word estimates as fully voiced. Both playback and WAV export now remove detected silence inside those intervals; new word boundaries also measure actual pauses for formatting.
- The normal Transcript view bypassed the existing pause presentation layer. It now shares paragraph and punctuation formatting with the audio-linked view while preserving original selection offsets. Regression tests cover the spaces left behind by a cut/delete operation.

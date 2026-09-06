# Speech-only functionality review

The React port must create entry content from speech and keep each spoken word attached to its original recording. The initial web implementation wrongly allowed keyboard entry. This review corrects that behavior and related additions rather than treating them as feature parity.

## Evidence in the recovered Swift app

- [`Main.storyboard`](../diction-processor/Base.lproj/Main.storyboard) declares the entry text view `editable="NO"`.
- [`SelectionCursor.pasteClipboard`](../diction-processor/SelectionCursor.swift) duplicates `EntrySegment` objects, retaining recorded segments rather than pasting arbitrary operating-system clipboard text. Selection and editing operate on segments.
- [`Entry.getTitle`](../diction-processor/Entry.swift) derives an entry title from its creation date/time when no stored title exists. The recovered app has no user-facing entry rename field.
- [`VoiceCommandEngine`](../diction-processor/VoiceCommandEngine.swift) supplies the active command identities and grammar; it does not define the extra comma/new-line/new-paragraph dictation shortcuts or a literal-prefix escape feature.
- Original playback and synthesized echo are separate capabilities in `SpeechPlayerEngine.swift` and `SpeechSynthesisEngine.swift`.
- The recovered source has no arbitrary audio-file import workflow. Retrying audio recorded by Lingual remains a recovery operation.

## Corrections

| Path | Current behavior |
| --- | --- |
| Main entry | Read-only transcript, no mobile typing keyboard, no editable title. Display names derive from creation time; existing saved titles are retained. |
| Replacement | Speak the candidate; accept, redo or cancel it. No typed draft input. |
| Selection editing | Selecting part of a word copies/deletes/replaces its whole recorded word. Dictating at a caret inside a word inserts after it. |
| Clipboard | Lingual's clipboard carries text with source timestamps, including between entries. Copy, cut and paste reject passages with missing audio. OS paste and drop cannot create content. |
| Inference | Reject a result with incomplete or invalid source timing. Keep its original saved recording available for retry. |
| Undo/redo | Restore words and audio together. Buttons, keyboard shortcuts and spoken commands use the same validation. Incomplete legacy snapshots cannot add unrecorded words. |
| Playback/export audio | Require a complete recorded passage. Do not silently synthesize missing words or omit unrecorded parts of a mixed passage. Explicit **Echo** remains the native synthesized read-back feature. |
| File input | Removed arbitrary audio-file import. Backup restore remains a browser-storage adaptation and validates audio coverage across current content, history and redo snapshots. |
| Dictation shortcuts | Removed extra punctuation-name/newline/select-all transformations and literal-prefix stripping. Use the original action vocabulary; turn voice actions off to speak a command phrase as entry content. |

Search and action-dictionary fields remain editable because they are queries. Model initialization, microphone permission, local backup/restore, and recording retry are required browser or recovery controls and do not create typed entry content.

Existing locally saved text is not erased. Legacy words without audio remain readable and exportable for recovery, are marked as missing their original recording, and cannot be duplicated as a spoken passage. A backup containing these words can still be exported for safekeeping; restore rejects it with an explanation rather than representing it as recorded speech.

## Verification

- `web/src/lib/speech-only.test.ts`: missing/partial timing, invalid timestamps, recorded replacement, clipboard rejection, partial-word selection/insertion/deletion/playback, repeated words, and legacy undo/redo.
- `web/src/lib/backup.test.ts`: current/history/future audio coverage and valid empty/recorded archives.
- `web/tests/speech-only.spec.ts`: read-only main/draft fields, keyboard insertion/backspace, paste/drop events, speech replacement and persistence, whole-word editing, ordinary phrase preservation, missing-audio playback/clipboard, and guarded button/keyboard history.
- Existing editor, selection, clipboard, walk/run, replacement and persistence browser workflows now record their fixtures through the real React/capture/storage path with deterministic microphone/model boundaries; they no longer fill an editable entry field.
- `yarn test:speech` runs real Whisper from the built static assets with synthetic microphone speech, including cold model loading, cached reload, restarted capture and source timing checks.

This correction does not close every previously documented behavior gap. The [184-item original test-note audit](test-specifications.md) still distinguishes automated coverage, partial coverage, missing features and device checks; complete native parity is not claimed.

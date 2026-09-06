# Punctuation and recorded words

Lingual keeps Whisper's recognized text, including punctuation, alongside immutable links to the original audio. Pause suggestions are a separate presentation layer. Turning **Punctuation suggestions** off hides recognized and inferred sentence punctuation from the entry views, previews, replacement draft, text export and Echo. Turning it on restores Whisper’s original marks. Apostrophes/hyphens inside words and numeric separators remain intact so spelling and numeric meaning do not change.

## What the Swift code does

`diction-processor/data-structures/PunctuationMap.swift` already maps the em dash (`—`) to “dash.” Its other names include comma, period, newline, exclamation mark, at sign, ampersand, plus, minus, colon, semi-colon, forward slash and question mark. The web tests read that file and verify those names directly.

`EntrySegment.swift` distinguishes explicit punctuation from silence-derived suggestions. Its thresholds, defined in `Utils.swift`, are strictly greater than 2 seconds (comma), 4 seconds (sentence), and 7 seconds (paragraph). It avoids adding punctuation beside existing punctuation, and uses conjunction, question and emphasis information to choose suggested marks.

The React layer follows that precedence and those thresholds. A missing paragraph ending now receives a sentence terminator before the paragraph break. Existing sentence endings can receive a paragraph break without a second terminator. Commas use common English conjunctions and the native adjacent-adjective rule. Question starters and measured emphasis influence missing sentence endings. Native valid-ending guards reject unfinished conjunctions, prepositions, determiners and adjectives, preserving their pronoun/predicate exceptions. Local English tagging replaces Apple NLTagger, using the final 32 words as context for sentence endings; tagging can differ between engines. Generated sentence/paragraph boundaries capitalize the following displayed word without rewriting source offsets. Four/seven-second anticipation cues and committed boundary notices precede passive Echo.

## How Whisper supplies punctuation

Whisper generates text tokens, including punctuation, during decoding. It does not expose a general `punctuation: false` switch. Token suppression can prevent selected token IDs, but that is a decoding constraint rather than a separate punctuation formatter. Lingual keeps normal punctuation generation enabled.

Whisper's word-alignment code merges many punctuation marks into neighboring words. The `prepend_punctuations` and `append_punctuations` settings govern that alignment; they do not switch punctuation generation on or off. Transformers.js 3.8.1, used here, also merges punctuation during word alignment.

Primary sources:

- [Whisper decoding and transcription options](https://github.com/openai/whisper/blob/main/whisper/transcribe.py)
- [Whisper punctuation merging and word timing](https://github.com/openai/whisper/blob/main/whisper/timing.py)
- [Transformers Whisper model documentation](https://huggingface.co/docs/transformers/model_doc/whisper)

## Text and audio rules

- Recognized punctuation is preserved, including curly quotes, em/en dashes, ellipses and unfamiliar Unicode marks. It is retained in storage when suggestions are disabled, but hidden in the displayed and exported text.
- Punctuation-only model chunks remain in the text but do not receive invented playback intervals. Words must still have valid original audio before insertion.
- A standalone dash does not count as a word. Words joined by an em dash are navigable separately; if the model timestamps the entire compound as one unit, editing/playback preserves that entire audio unit instead of estimating new timestamps by character position.
- The read-only Transcript view, audio-linked view, text export and Echo share the same derived pause punctuation and visibility. Character mappings preserve original audio offsets, including carets inside multiple spaces left by a cut or deletion. Sentence/paragraph commands map those displayed boundaries back to original text/audio indices. Echo highlights and rate-change continuation also map expanded punctuation names back to the original words.
- Decimal points and common abbreviations stay within sentence units. Closing quotes remain with their sentences. When punctuation is visible, explicit punctuation Echo extends the native vocabulary to ellipses, quotes and brackets while keeping contractions, numeric separators and hyphenated words intact.
- Stored entries and backups retain their existing schema. Presentation changes do not rewrite past recordings or stored text.

## Verification

`web/src/lib/punctuation-display.test.ts` covers removal/restoration, spelling/number safety, hidden-quote carets and selection mapping. `web/src/lib/punctuation.test.ts` covers native names, strict pause thresholds, existing punctuation, suggestion toggles, Unicode punctuation, sentence selection, decimal numbers, contractions, compound audio timestamps and punctuation-only model chunks. The existing timeline, editor, command, capture, backup and prosody suites run alongside it.

`web/tests/punctuation.spec.ts` exercises hiding/restoring punctuation through recording, audio-linked rendering, preferences, copying/pasting, undo, reload and text export, plus punctuation Echo highlights and rate-change continuation. It also verifies a centered listening button at desktop/mobile widths, no idle instruction or waveform, and a visible recording timer while listening. These deterministic tests control only the microphone/model boundary. `yarn test:speech` separately exercises the real bundled Whisper model and capture pipeline with synthetic speech.

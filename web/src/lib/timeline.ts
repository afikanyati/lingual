import type { Entry, TextSelection } from "../interfaces/entry";
import type {
  AudioSpan,
  Passage,
  PlaybackSlice,
  Transcript,
} from "../interfaces/timeline";
import { containsWords } from "./punctuation";
import { replaceRange, snapshot } from "./editor";
import { hasCompleteAudio, recordedSelection } from "./audio-integrity";

/** Position the caret or selection on the edited audio timeline, including retained pauses and word rates. */
export function selectionAudioTime(
  entry: Entry,
  omitSilences: boolean,
): TextSelection {
  let elapsed = 0;
  let start: number | undefined;
  let end: number | undefined;
  for (const slice of playbackSlices(
    entry,
    { start: 0, end: entry.text.length },
    omitSilences,
  )) {
    if (start === undefined && slice.textEnd > entry.selection.start)
      start = elapsed;
    elapsed += (slice.end - slice.start) / slice.rate;
    if (slice.textStart < entry.selection.end) end = elapsed;
  }
  const position = start ?? elapsed;
  return {
    start: position,
    end:
      entry.selection.start === entry.selection.end
        ? position
        : (end ?? position),
  };
}

/** Keep immutable links to source audio; edited playback is a sequence of slices, never a rewritten original. */
export function copyPassage(entry: Entry, range: TextSelection): Passage {
  range = recordedSelection(entry.text, range, entry.spans);
  return {
    text: entry.text.slice(range.start, range.end),
    spans: entry.spans
      .filter((span) => span.start < range.end && span.end > range.start)
      .map((span) => {
        const start = Math.max(range.start, span.start);
        const end = Math.min(range.end, span.end);
        const duration = span.sourceEnd - span.sourceStart;
        const length = span.end - span.start;
        return {
          ...span,
          start: start - range.start,
          end: end - range.start,
          sourceStart:
            span.sourceStart + (duration * (start - span.start)) / length,
          sourceEnd:
            span.sourceStart + (duration * (end - span.start)) / length,
        };
      }),
  };
}
export function insertPassage(
  entry: Entry,
  passage: Passage,
  isDictation = true,
): Entry {
  if (!passage.text) return entry;
  if (!hasCompleteAudio(passage))
    throw new Error(
      "Every word needs its original recording. Speak the passage again or retry its saved audio.",
    );
  const { start, end } = recordedSelection(
    entry.text,
    entry.selection,
    entry.spans,
  );
  const before = entry.text.slice(0, start);
  const after = entry.text.slice(end);
  const prefix =
    before &&
    !/\s$/.test(before) &&
    !/^[\s.,!?;:…—–\p{Pe}\p{Pf}]/u.test(passage.text)
      ? " "
      : "";
  const suffix =
    after &&
    !/^[\s.,!?;:…—–\p{Pe}\p{Pf}]/u.test(after) &&
    !/\s$/.test(passage.text)
      ? " "
      : "";
  const result = replaceRange(
    entry,
    start,
    end,
    prefix + passage.text + suffix,
    passage.spans.length > 0,
  );
  const inserted = passage.spans.map((span) => ({
    ...span,
    start: span.start + start + prefix.length,
    end: span.end + start + prefix.length,
  }));
  const commit = {
    start: start + prefix.length,
    end: start + prefix.length + passage.text.length,
  };
  return {
    ...result,
    commits: isDictation ? [...(result.commits ?? []), commit] : result.commits,
    spans: [...result.spans, ...inserted].sort((a, b) => a.start - b.start),
    clipIds: [
      ...new Set([...result.clipIds, ...inserted.map((span) => span.clipId)]),
    ],
    lastCommit: isDictation ? commit : result.lastCommit,
  };
}

/** Native paste inserts after the anchor word and keeps the selection's original audio. */
export function pastePassage(entry: Entry, passage: Passage): Entry {
  if (!passage.text) return entry;
  const selected = entry.selection.end > entry.selection.start;
  const anchor = selected
    ? entry.spans.find((span) => span.end > entry.selection.start)?.end
    : entry.selection.start;
  const position = anchor ?? entry.selection.start;
  const result = insertPassage(
    { ...entry, selection: { start: position, end: position } },
    passage,
    false,
  );
  return {
    ...result,
    history: [...result.history.slice(0, -1), snapshot(entry)],
  };
}
export function applySpanRate(
  entry: Entry,
  range: TextSelection,
  delta: number,
): Entry {
  const intersects = entry.spans.some(
    (span) => span.start < range.end && span.end > range.start,
  );
  if (!intersects) return entry;
  return {
    ...entry,
    spans: entry.spans.map((span) =>
      span.start < range.end && span.end > range.start
        ? {
            ...span,
            rate: Math.max(
              0.2,
              Math.min(3, Number((span.rate + delta).toFixed(2))),
            ),
          }
        : span,
    ),
    history: [...entry.history.slice(-99), snapshot(entry)],
    future: [],
    updatedAt: new Date().toISOString(),
  };
}
export function playbackSlices(
  entry: Entry,
  range: TextSelection,
  omitSilences: boolean,
): PlaybackSlice[] {
  range = recordedSelection(entry.text, range, entry.spans);
  const spans = copyPassage(entry, range).spans;
  const slices: PlaybackSlice[] = [];
  for (const span of spans) {
    const previous = slices.at(-1);
    const originalPrevious = spans[spans.indexOf(span) - 1];
    const adjacent =
      originalPrevious &&
      (span.ordinal !== undefined && originalPrevious.ordinal !== undefined
        ? span.ordinal === originalPrevious.ordinal + 1
        : span.sourceStart - originalPrevious.sourceEnd < 0.31);
    if (
      !omitSilences &&
      previous &&
      adjacent &&
      previous.clipId === span.clipId &&
      previous.rate === span.rate &&
      previous.gain === span.gain &&
      span.sourceStart >= previous.end
    ) {
      // Keep each word independently addressable while retaining the pause before the next word.
      previous.end = span.sourceStart;
    }
    slices.push({
      ...(omitSilences ? { omitSilences: true } : {}),
      clipId: span.clipId,
      start: span.sourceStart,
      end: span.sourceEnd,
      rate: span.rate,
      gain: span.gain,
      textStart: span.start + range.start,
      textEnd: span.end + range.start,
    });
  }
  return slices.filter((slice) => slice.end > slice.start);
}

/** Use actual Whisper word timestamps, not estimated positions in a whole recording. */
export function transcriptPassage(
  transcript: Transcript,
  clipId: string,
): Passage {
  const spans: AudioSpan[] = [];
  let cursor = 0;
  for (const word of transcript.words) {
    const text = word.text.trim();
    const start = transcript.text.indexOf(text, cursor);
    if (start < 0 || !text) continue;
    cursor = start + text.length;
    // Decoder punctuation is formatting. Do not manufacture an audio interval for a punctuation-only chunk.
    if (!containsWords(text) || word.end <= word.start) continue;
    spans.push({
      start,
      end: start + text.length,
      clipId,
      sourceStart: word.start,
      sourceEnd: word.end,
      rate: 1,
      gain: 1,
      // Ordinals track spoken words, so a formatting chunk does not interrupt original-audio adjacency.
      ordinal: spans.length,
    });
  }
  return { text: transcript.text, spans };
}

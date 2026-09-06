import { spokenWordRanges } from "./punctuation";
import type { AudioSpan, Passage } from "../interfaces/timeline";
import type { TextSelection } from "../interfaces/entry";

/** Every spoken word must be covered by valid source-audio intervals; spacing/punctuation are formatting. */
export function hasCompleteAudio(passage: Passage): boolean {
  const spans = [...passage.spans].sort((a, b) => a.start - b.start);
  if (
    spans.some(
      (span) =>
        !span.clipId ||
        !Number.isFinite(span.sourceStart) ||
        !Number.isFinite(span.sourceEnd) ||
        span.sourceStart < 0 ||
        span.sourceEnd <= span.sourceStart ||
        !Number.isInteger(span.start) ||
        !Number.isInteger(span.end) ||
        span.start < 0 ||
        span.end > passage.text.length ||
        span.end <= span.start,
    )
  )
    return false;
  let index = 0;
  for (const word of passage.text.matchAll(/[\p{L}\p{N}]+/gu)) {
    let covered = word.index!;
    const end = covered + word[0].length;
    while (index < spans.length && spans[index].end <= covered) index++;
    for (
      let current = index;
      current < spans.length && covered < end;
      current++
    ) {
      if (spans[current].start > covered) break;
      covered = Math.max(covered, spans[current].end);
    }
    if (covered < end) return false;
  }
  return true;
}

/** Native edits operate on recorded words, so a character selection must never split their source audio. */
export function recordedSelection(
  text: string,
  selection: TextSelection,
  spans: AudioSpan[] = [],
): TextSelection {
  let start = Math.max(
    0,
    Math.min(text.length, Math.min(selection.start, selection.end)),
  );
  let end = Math.max(
    start,
    Math.min(text.length, Math.max(selection.start, selection.end)),
  );
  const words = spokenWordRanges(text);
  if (start === end) {
    const word = words.find((word) => word.start < start && word.end > start);
    if (word) start = end = word.end;
    const audio = spans.find((span) => span.start < start && span.end > start);
    if (audio) start = end = audio.end;
    return { start, end };
  }
  for (const word of words) {
    const wordStart = word.start;
    const wordEnd = word.end;
    if (wordEnd <= start || wordStart >= end) continue;
    start = Math.min(start, wordStart);
    end = Math.max(end, wordEnd);
  }
  // A model may timestamp a compound as one unit. Preserve the entire unit rather than estimate new word times.
  for (const span of [...spans].sort((a, b) => a.start - b.start)) {
    if (span.end <= start || span.start >= end) continue;
    start = Math.min(start, span.start);
    end = Math.max(end, span.end);
  }
  return { start, end };
}

import {
  containsWords,
  punctuationPresentation,
  punctuationForEcho,
  sentenceRanges,
  textFragments,
} from "./punctuation";
import { speechIntervals } from "./speech-pauses";
import { adjacentAdjectives, canEndSentence } from "./linguistics";
import type { TextPresentation, TextFragment } from "../interfaces/text";
import type { Passage } from "../interfaces/timeline";
import type { Preferences } from "../interfaces/workspace";
import type { Entry, TextSelection } from "../interfaces/entry";

export { estimatePitch, powerDb } from "./pitch";
import { powerDb, wordPitch } from "./pitch";
export function annotateProsody(
  passage: Passage,
  audio: Float32Array,
): Passage {
  // Whisper's alignment can include leading/trailing silence in a word. Keep immutable audio,
  // but measure pauses from audible boundaries rather than those broad model estimates.
  passage = {
    ...passage,
    spans: passage.spans.map((span) => {
      const intervals = speechIntervals(
        audio,
        span.sourceStart,
        span.sourceEnd,
      );
      return {
        ...span,
        sourceStart: intervals[0].start,
        sourceEnd: intervals.at(-1)!.end,
      };
    }),
  };
  const powers = passage.spans.map((span) =>
    powerDb(
      audio.subarray(
        Math.floor(span.sourceStart * 16000),
        Math.ceil(span.sourceEnd * 16000),
      ),
    ),
  );
  const mean = powers.length
    ? powers.reduce((sum, value) => sum + value, 0) / powers.length
    : -160;
  return {
    ...passage,
    spans: passage.spans.map((span, index) => ({
      ...span,
      power: powers[index],
      emphasized: powers[index] > mean + 10,
      pitch: wordPitch(
        audio.subarray(
          Math.floor(span.sourceStart * 16000),
          Math.ceil(span.sourceEnd * 16000),
        ),
      ),
      speakingRate: 1 / Math.max(0.05, span.sourceEnd - span.sourceStart),
    })),
  };
}

/** Recognition stays untouched; punctuation visibility and capitalization are presentation preferences. */
export function displayWord(
  word: string,
  _recorded: boolean,
  preferences: Preferences,
): string {
  const displayed = punctuationPresentation(
    word,
    preferences.punctuationSuggestions,
  ).text;
  return preferences.capitalization ? displayed : displayed.toLowerCase();
}

/** Apply the native pause thresholds only where Whisper has not already supplied a boundary mark. */
export function displayGap(
  entry: Entry,
  start: number,
  end: number,
  preferences: Preferences,
): string {
  const original = entry.text.slice(start, end);
  if (original !== " ")
    return punctuationPresentation(original, preferences.punctuationSuggestions)
      .text;
  const previous = [...entry.spans].reverse().find((span) => span.end <= start);
  const next = entry.spans.find((span) => span.start >= end);
  if (!previous || !next) return original;
  // Only the silence between these words is eligible; never jump across other words or treat deleted audio as silence.
  if (
    containsWords(entry.text.slice(previous.end, start)) ||
    containsWords(entry.text.slice(end, next.start))
  )
    return original;
  if (
    previous.clipId === next.clipId &&
    previous.ordinal !== undefined &&
    next.ordinal !== undefined &&
    next.ordinal !== previous.ordinal + 1
  )
    return original;
  const sameSession =
    previous.recordingId && previous.recordingId === next.recordingId;
  const pause =
    sameSession &&
    next.recordedStart !== undefined &&
    previous.recordedEnd !== undefined
      ? next.recordedStart - previous.recordedEnd
      : previous.clipId === next.clipId
        ? next.sourceStart - previous.sourceEnd
        : 0;
  const before = entry.text.slice(0, start);
  const after = entry.text.slice(end);
  const terminal = /[.!?…。！？][\p{Pe}\p{Pf}"']*$/u.test(before);
  const existingMark =
    /[\p{P}\p{S}]$/u.test(before) || /^[\p{P}\p{S}]/u.test(after);
  // Native Utils.swift uses >2 / >4 / >7 seconds; EntrySegment.getText avoids existing punctuation.
  if (preferences.punctuationSuggestions) {
    if (pause > 7 && terminal) return "\n\n";
    if (!existingMark) {
      // Match the native question-opening heuristic, leaving Whisper's existing question marks authoritative.
      const sentence =
        before
          .split(/[.!?\n]/u)
          .at(-1)
          ?.trim()
          .toLowerCase() ?? "";
      const question =
        /^(which|won't|can't|isn't|aren't|is|do|does|will|can|did|has|had|are|were|could|may|might|would|shall|should|must|am|was|have|who|what|when|where|why|how)\b/u.test(
          sentence,
        );
      const terminator = question
        ? previous.emphasized
          ? "?!"
          : "?"
        : previous.emphasized
          ? "!"
          : ".";
      if (pause > 7 && canEndSentence(before)) return `${terminator}\n\n`;
      if (pause > 4 && canEndSentence(before)) return `${terminator} `;
      // Swift uses NLTag.conjunction. This English fallback conservatively covers common conjunctions.
      if (
        pause > 2 &&
        /^(and|but|or|nor|for|so|yet|because|although|though|while|unless|if|when|whereas)\b/iu.test(
          after,
        )
      )
        return ", ";
      if (adjacentAdjectives(entry.text, start)) return ", ";
    }
  }
  if (preferences.temporalSuggestions && pause > 4)
    return " ".repeat(Math.min(3600, Math.ceil(2 * pause)));
  return original;
}

/** Every rendered fragment keeps its source range so generated punctuation never shifts stored audio offsets. */
export function presentationFragments(
  entry: Entry,
  preferences: Preferences,
  range: TextSelection,
): TextFragment[] {
  const previous = textFragments(entry.text.slice(0, range.start)).at(-1);
  let capitalizeNext = Boolean(
    previous &&
      !containsWords(previous.text) &&
      /[.!?\n]/u.test(
        displayGap(entry, previous.start, previous.end, preferences),
      ) &&
      displayGap(entry, previous.start, previous.end, preferences) !==
        previous.text,
  );
  return textFragments(entry.text.slice(range.start, range.end)).map(
    (fragment) => {
      const start = fragment.start + range.start;
      const end = fragment.end + range.start;
      if (!containsWords(fragment.text)) {
        const text = displayGap(entry, start, end, preferences);
        capitalizeNext = text !== fragment.text && /[.!?\n]/u.test(text);
        return { start, end, text };
      }
      let text = displayWord(fragment.text, true, preferences);
      if (capitalizeNext && preferences.capitalization)
        text = text.replace(/^[a-z]/u, (letter) => letter.toUpperCase());
      capitalizeNext = false;
      return { start, end, text };
    },
  );
}

/** Announce newly committed pause boundaries before passive echo, without replaying older notices. */
export function commitNotifications(
  entry: Entry,
  range: TextSelection,
  preferences: Preferences,
): string[] {
  if (!preferences.punctuationSuggestions) return [];
  return presentationFragments(entry, preferences, {
    start: 0,
    end: entry.text.length,
  })
    .filter(
      (fragment) =>
        fragment.end >= range.start &&
        fragment.start < range.end &&
        !containsWords(entry.text.slice(fragment.start, fragment.end)),
    )
    .flatMap((fragment) => {
      if (fragment.text === entry.text.slice(fragment.start, fragment.end))
        return [];
      if (fragment.text.includes("\n\n")) return ["New paragraph"];
      return /[.!?]/u.test(fragment.text) ? ["New sentence"] : [];
    });
}

/** Export and echo share the audio-linked view's punctuation; the stored recognition text remains untouched. */
export function presentedText(
  entry: Entry,
  preferences: Preferences,
  range: TextSelection,
  forEcho = false,
): string {
  return (
    forEcho
      ? echoFragments(entry, preferences, range)
      : presentationFragments(entry, preferences, range)
  )
    .map((fragment) => fragment.text)
    .join("");
}

/** Keep spoken punctuation names mapped to their original transcript fragment. */
export function echoFragments(
  entry: Entry,
  preferences: Preferences,
  range: TextSelection,
): TextFragment[] {
  return presentationFragments(entry, preferences, range).map((fragment) => ({
    ...fragment,
    text: preferences.punctuation
      ? punctuationForEcho(fragment.text)
      : fragment.text,
  }));
}

/** Speech engines report offsets in the expanded utterance, not the stored transcript. */
export function echoSourceRange(
  fragments: TextFragment[],
  offset: number,
): TextSelection | undefined {
  let end = 0;
  for (const fragment of fragments) {
    end += fragment.text.length;
    if (end > offset) return { start: fragment.start, end: fragment.end };
  }
}

/** Translate displayed sentence/paragraph boundaries back to immutable transcript indices for editing and playback. */
export function presentedUnitRanges(
  entry: Entry,
  preferences: Preferences,
  unit: "sentence" | "paragraph",
): TextSelection[] {
  const fragments = presentationFragments(entry, preferences, {
    start: 0,
    end: entry.text.length,
  });
  let offset = 0;
  const mapped = fragments.map((fragment) => {
    const result = {
      ...fragment,
      renderedStart: offset,
      renderedEnd: offset + fragment.text.length,
    };
    offset = result.renderedEnd;
    return result;
  });
  const text = fragments.map((fragment) => fragment.text).join("");
  const ranges =
    unit === "sentence"
      ? sentenceRanges(text)
      : [...text.matchAll(/[^\n]+(?:\n(?!\n)[^\n]+)*/g)].map((match) => ({
          start: match.index!,
          end: match.index! + match[0].trimEnd().length,
        }));
  // ICU can treat a period before a lowercase word as an abbreviation. A pause-generated boundary is explicit.
  const forced = mapped
    .filter(
      (fragment) =>
        fragment.text !== entry.text.slice(fragment.start, fragment.end) &&
        (unit === "sentence" ? /[.!?\n]/u : /\n\n/u).test(fragment.text),
    )
    .map((fragment) => fragment.renderedEnd);
  const separated = ranges.flatMap((range) => {
    const edges = [
      range.start,
      ...forced.filter((edge) => edge > range.start && edge < range.end),
      range.end,
    ];
    return edges.slice(1).map((end, index) => ({ start: edges[index], end }));
  });
  return separated
    .map((range) => {
      const words = mapped.filter(
        (fragment) =>
          fragment.renderedStart < range.end &&
          fragment.renderedEnd > range.start &&
          containsWords(fragment.text),
      );
      return { start: words[0]?.start ?? 0, end: words.at(-1)?.end ?? 0 };
    })
    .filter((range) => range.end > range.start);
}

/** Compose pause formatting and punctuation visibility without moving the stored text/audio selections. */
export function entryPresentation(
  entry: Entry,
  preferences: Preferences,
): TextPresentation {
  const result: TextPresentation = {
    text: "",
    sourceStarts: [],
    sourceEnds: [],
    sourceLength: entry.text.length,
  };
  const presented = presentationFragments(entry, preferences, {
    start: 0,
    end: entry.text.length,
  });
  for (const [index, fragment] of textFragments(entry.text).entries()) {
    if (containsWords(fragment.text)) {
      const word = punctuationPresentation(
        fragment.text,
        preferences.punctuationSuggestions,
      );
      result.text += presented[index].text;
      result.sourceStarts.push(
        ...word.sourceStarts.map((offset) => offset + fragment.start),
      );
      result.sourceEnds.push(
        ...word.sourceEnds.map((offset) => offset + fragment.start),
      );
      continue;
    }
    const gap = presented[index].text;
    result.text += gap;
    const originalGap = punctuationPresentation(
      fragment.text,
      preferences.punctuationSuggestions,
    );
    if (gap === originalGap.text) {
      result.sourceStarts.push(
        ...originalGap.sourceStarts.map((offset) => offset + fragment.start),
      );
      result.sourceEnds.push(
        ...originalGap.sourceEnds.map((offset) => offset + fragment.start),
      );
      continue;
    }
    for (let index = 0; index < gap.length; index++) {
      result.sourceStarts.push(fragment.start);
      result.sourceEnds.push(fragment.end);
    }
  }
  return result;
}

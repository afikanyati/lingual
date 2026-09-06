import type { TextSelection } from "../interfaces/entry";
import type { TextFragment, TextPresentation } from "../interfaces/text";

/** Dashes between words are formatting boundaries, not additional spoken words. */
export function textFragments(text: string): TextFragment[] {
  return [...text.matchAll(/[\s—–]+|[^\s—–]+/gu)].map((match) => ({
    text: match[0],
    start: match.index!,
    end: match.index! + match[0].length,
  }));
}
export function containsWords(text: string): boolean {
  return /[\p{L}\p{N}]/u.test(text);
}
export function spokenWordRanges(text: string): TextSelection[] {
  return textFragments(text)
    .filter((fragment) => containsWords(fragment.text))
    .map(({ start, end }) => ({ start, end }));
}
/** Unicode sentence segmentation keeps closing quotes with sentences and decimal points within numbers. */
export function sentenceRanges(text: string): TextSelection[] {
  const segmenter = new Intl.Segmenter("en", { granularity: "sentence" });
  const boundaries = new Set([0, text.length]);
  for (const { segment, index } of segmenter.segment(text)) {
    boundaries.add(index + segment.length);
  }
  // ICU can merge full stops before lowercase dictation. Add these explicit boundaries too.
  for (const match of text.matchAll(/[.!?…。！？]+[\p{Pe}\p{Pf}"']*\s+/gu)) {
    boundaries.add(match.index! + match[0].length);
  }
  const edges = [...boundaries]
    .sort((a, b) => a - b)
    .filter((end) => {
      if (end === 0 || end === text.length) return true;
      // Protect common English abbreviations and initials even if ICU separated them.
      return !/(?:\b(?:mr|mrs|ms|dr|prof|sr|jr|st|vs|etc)|\b[A-Za-z]|(?:[A-Za-z]\.)+[A-Za-z])\.\s*$/iu.test(
        text.slice(Math.max(0, end - 40), end),
      );
    });
  return edges
    .slice(1)
    .map((end, position) => {
      const start = edges[position];
      const part = text.slice(start, end);
      return {
        start: start + (part.match(/^\s*/)?.[0].length ?? 0),
        end: start + part.trimEnd().length,
      };
    })
    .filter((range) => range.end > range.start);
}

// Native names are verified against diction-processor/data-structures/PunctuationMap.swift by punctuation.test.ts.
const punctuationNames: Record<string, string> = {
  ",": "comma",
  ".": "period",
  "—": "dash",
  "\n": "newline",
  "!": "exclamation mark",
  "@": "at sign",
  "&": "ampersand",
  "+": "plus",
  "-": "minus",
  ":": "colon",
  ";": "semi-colon",
  "/": "forward slash",
  "?": "question mark",
  "–": "dash",
  "…": "ellipsis",
  '"': "quote",
  "'": "apostrophe",
  "“": "open quote",
  "”": "close quote",
  "‘": "open quote",
  "’": "close quote",
  "(": "open parenthesis",
  ")": "close parenthesis",
  "[": "open bracket",
  "]": "close bracket",
  "{": "open brace",
  "}": "close brace",
  _: "underscore",
  "\\": "backslash",
  "。": "period",
  "，": "comma",
  "、": "comma",
  "！": "exclamation mark",
  "？": "question mark",
  "：": "colon",
  "；": "semi-colon",
};

/** Punctuation inside a word or number carries meaning and should not be expanded into a separate utterance. */
function isLexicalMark(text: string, index: number, mark: string): boolean {
  const before = text[index - 1] ?? "";
  const after = text[index + 1] ?? "";
  if (
    /[’'ʼ-]/u.test(mark) &&
    /[\p{L}\p{N}]/u.test(before) &&
    /[\p{L}\p{N}]/u.test(after)
  )
    return true;
  if (/[.,:/]/u.test(mark) && /\d/u.test(before) && /\d/u.test(after))
    return true;
  if (mark === ".") {
    for (const abbreviation of text.matchAll(/(?:[A-Za-z]\.){2,}/g)) {
      if (
        index >= abbreviation.index! &&
        index < abbreviation.index! + abbreviation[0].length
      )
        return true;
    }
  }
  return false;
}

/** Explicit punctuation echo uses the native vocabulary and preserves unfamiliar Unicode marks instead of dropping them. */
export function punctuationForEcho(text: string): string {
  return text.replace(/\r\n|\.{3,}|[\p{P}\p{S}\n]/gu, (mark, index: number) => {
    if (isLexicalMark(text, index, mark)) return mark;
    const name = /^\.{3,}$/.test(mark)
      ? "ellipsis"
      : punctuationNames[mark === "\r\n" ? "\n" : mark];
    return name ? ` ${name} ` : mark;
  });
}

/** Hide sentence punctuation while preserving spelling/number separators and original character offsets. */
export function punctuationPresentation(
  text: string,
  visible: boolean,
): TextPresentation {
  const result: TextPresentation = {
    text: "",
    sourceStarts: [],
    sourceEnds: [],
    sourceLength: text.length,
  };
  let offset = 0;
  for (const character of text) {
    const start = offset;
    offset += character.length;
    let displayed = character;
    if (
      !visible &&
      /\p{P}/u.test(character) &&
      !isLexicalMark(text, start, character)
    ) {
      const joinsWords =
        /[\p{L}\p{N}]/u.test(text[start - 1] ?? "") &&
        /[\p{L}\p{N}]/u.test(text[offset] ?? "");
      displayed = /[—–]/u.test(character) || joinsWords ? " " : "";
    }
    if (!visible && displayed === " " && result.text.endsWith(" ")) continue;
    result.text += displayed;
    for (let index = 0; index < displayed.length; index++) {
      result.sourceStarts.push(start + Math.min(index, character.length - 1));
      result.sourceEnds.push(start + Math.min(index + 1, character.length));
    }
  }
  return result;
}

/** Read-only textarea selections use visible offsets; editing always uses original transcript offsets. */
export function sourceSelection(
  view: TextPresentation,
  selection: TextSelection,
): TextSelection {
  const start = view.sourceStarts[selection.start] ?? view.sourceLength;
  if (selection.start === selection.end) {
    // At a word boundary, remain before any hidden opening quote; never snap inside the next word.
    const caret =
      selection.start === view.text.length
        ? view.sourceLength
        : (view.sourceEnds[selection.start - 1] ?? 0);
    return { start: caret, end: caret };
  }
  return {
    start,
    end: view.sourceEnds[selection.end - 1] ?? view.sourceLength,
  };
}

/** Restore a recorded selection after a command, using the current punctuation setting. */
export function displaySelection(
  view: TextPresentation,
  selection: TextSelection,
): TextSelection {
  const start = view.sourceEnds.findIndex((end) => end > selection.start);
  const end = view.sourceStarts.findIndex((start) => start >= selection.end);
  return {
    start: start < 0 ? view.text.length : start,
    end: end < 0 ? view.text.length : end,
  };
}

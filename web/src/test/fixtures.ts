import { createEntry } from "../lib/editor";
import { insertPassage } from "../lib/timeline";
import { defaultPreferences } from "../lib/commands";
import type { CommandContext } from "../interfaces/workspace";
import type { Passage } from "../interfaces/timeline";

/** Synthetic word timings make edits verifiable without personal recordings or a model download. */
export function spokenPassage(
  text = "one two three four five six seven eight",
  clipId = "original",
): Passage {
  return {
    text,
    spans: [...text.matchAll(/\S+/g)].map((match, ordinal) => ({
      start: match.index!,
      end: match.index! + match[0].length,
      clipId,
      ordinal,
      sourceStart: ordinal,
      sourceEnd: ordinal + 0.5,
      rate: 1,
      gain: 1,
    })),
  };
}
export function spokenContext(): CommandContext {
  return {
    entry: {
      ...insertPassage(createEntry(), spokenPassage()),
      selection: { start: 4, end: 18 },
    },
    preferences: { ...defaultPreferences },
    clipboard: spokenPassage("new words", "clipboard"),
  };
}

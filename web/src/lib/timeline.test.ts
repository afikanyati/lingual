import { describe, it, expect } from "vitest";
import { createEntry, replaceRange, undo, redo } from "./editor";
import {
  insertPassage,
  copyPassage,
  playbackSlices,
  applySpanRate,
} from "./timeline";
import { spokenPassage } from "../test/fixtures";
import type { Passage } from "../interfaces/timeline";
const spoken: Passage = {
  text: "one two three",
  spans: [
    {
      start: 0,
      end: 3,
      clipId: "a",
      sourceStart: 0,
      sourceEnd: 0.3,
      rate: 1,
      gain: 1,
    },
    {
      start: 4,
      end: 7,
      clipId: "a",
      sourceStart: 0.5,
      sourceEnd: 0.8,
      rate: 1,
      gain: 1,
    },
    {
      start: 8,
      end: 13,
      clipId: "a",
      sourceStart: 1,
      sourceEnd: 1.5,
      rate: 1,
      gain: 1,
    },
  ],
};
describe("synchronized text and audio editing", () => {
  it("deletion changes playback and undo restores the audio, not only text", () => {
    const entry = insertPassage(createEntry(), spoken);
    const removed = replaceRange(entry, 4, 8, "");
    expect(removed.text).toBe("one three");
    expect(
      playbackSlices(removed, { start: 0, end: 9 }, true).map(
        (item) => item.start,
      ),
    ).toEqual([0, 1]);
    expect(undo(removed).spans).toEqual(entry.spans);
    expect(redo(undo(removed)).spans).toEqual(removed.spans);
  });
  it("pasting in another entry preserves original source timestamps and order", () => {
    const first = insertPassage(createEntry(), spoken);
    const clipboard = copyPassage(first, { start: 4, end: 7 });
    const pasted = insertPassage(createEntry(), clipboard);
    expect(pasted.text).toBe("two");
    expect(pasted.spans[0]).toMatchObject({
      start: 0,
      end: 3,
      sourceStart: 0.5,
      sourceEnd: 0.8,
      clipId: "a",
    });
    expect(pasted.clipIds).toContain("a");
  });
  it("spoken replacements retain later audio offsets and supply their own recording", () => {
    const entry = insertPassage(createEntry(), spoken);
    const changed = insertPassage(
      { ...entry, selection: { start: 4, end: 7 } },
      spokenPassage("lovely", "replacement"),
    );
    expect(changed.spans.find((span) => span.sourceStart === 1)).toMatchObject({
      start: 11,
      end: 16,
    });
    expect(playbackSlices(changed, { start: 0, end: 16 }, true)).toHaveLength(
      3,
    );
  });
  it("rate edits are bounded, apply only to the selected audio, and are undoable", () => {
    const entry = insertPassage(createEntry(), spoken);
    const changed = applySpanRate(entry, { start: 4, end: 7 }, 0.2);
    expect(changed.spans.map((span) => span.rate)).toEqual([1, 1.2, 1]);
    expect(undo(changed).spans).toEqual(entry.spans);
  });
  it("retains pauses only between adjacent unedited source words", () => {
    const entry = insertPassage(createEntry(), spoken);
    const slices = playbackSlices(entry, { start: 0, end: 13 }, false);
    expect(slices).toHaveLength(3);
    expect(slices[0]).toMatchObject({ end: 0.5, textStart: 0, textEnd: 3 });
    const cut = replaceRange(entry, 4, 8, "");
    expect(playbackSlices(cut, { start: 0, end: 9 }, false)).toHaveLength(2);
  });
});
import { selectionAudioTime } from "./timeline";
import { createEntry as blankEntry } from "./editor";
import { spokenPassage as timedPassage } from "../test/fixtures";
it("maps the cursor and selected words to edited audio time, respecting speed changes", () => {
  const passage = timedPassage("one two three");
  passage.spans = passage.spans.map((span, index) => ({
    ...span,
    sourceStart: index,
    sourceEnd: index + 1,
    rate: index === 0 ? 2 : 1,
  }));
  const entry = {
    ...blankEntry(),
    ...passage,
    selection: { start: 4, end: 7 },
  };
  expect(selectionAudioTime(entry, true)).toEqual({ start: 0.5, end: 1.5 });
  expect(
    selectionAudioTime({ ...entry, selection: { start: 13, end: 13 } }, true),
  ).toEqual({ start: 2.5, end: 2.5 });
});

import { expect, it } from "vitest";
import { speechIntervals } from "./speech-pauses";
import { entryPresentation } from "./prosody";
import { sourceSelection, displaySelection } from "./punctuation";
import { createEntry } from "./editor";
import { defaultPreferences } from "./commands";

it("removes long internal and edge silence without cutting short phonetic gaps", () => {
  const audio = new Float32Array(32000);
  audio.fill(0.1, 3200, 8000);
  audio.fill(0.03, 8400, 11200); // 25 ms within a word stays intact
  audio.fill(0.1, 24000, 28800);
  expect(speechIntervals(audio, 0, 2)).toEqual([
    { start: 0.17, end: 0.73 },
    { start: 1.47, end: 1.83 },
  ]);
});
it("does not destroy quiet speech or an interval with no confidently detected speech", () => {
  expect(speechIntervals(new Float32Array(16000).fill(0.002), 0, 1)).toEqual([
    { start: 0, end: 1 },
  ]);
  expect(speechIntervals(new Float32Array(16000), 0, 1)).toEqual([
    { start: 0, end: 1 },
  ]);
});
it("renders a long pause in the transcript and keeps selections tied to the original audio", () => {
  const entry = {
    ...createEntry(),
    text: "Hello. Again!",
    spans: [
      {
        clipId: "a",
        start: 0,
        end: 6,
        sourceStart: 0,
        sourceEnd: 1,
        rate: 1,
        gain: 1,
      },
      {
        clipId: "a",
        start: 7,
        end: 13,
        sourceStart: 9,
        sourceEnd: 10,
        rate: 1,
        gain: 1,
      },
    ],
  };
  const view = entryPresentation(entry, defaultPreferences);
  expect(view.text).toBe("Hello.\n\nAgain!");
  expect(sourceSelection(view, { start: 8, end: 14 })).toEqual({
    start: 7,
    end: 13,
  });
  const plain = entryPresentation(entry, {
    ...defaultPreferences,
    punctuationSuggestions: false,
  });
  expect(plain.text).toBe("Hello Again");
  expect(sourceSelection(plain, { start: 6, end: 11 })).toEqual({
    start: 7,
    end: 12,
  });
  expect(entry.text).toBe("Hello. Again!");
});

it("preserves carets inside original multiple spaces after cut/delete", () => {
  const view = entryPresentation(
    { ...createEntry(), text: "one  three" },
    defaultPreferences,
  );
  expect(displaySelection(view, { start: 4, end: 4 })).toEqual({
    start: 4,
    end: 4,
  });
  expect(sourceSelection(view, { start: 4, end: 4 })).toEqual({
    start: 4,
    end: 4,
  });
});

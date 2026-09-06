import { describe, it, expect } from "vitest";
import { estimatePitch, powerDb, presentedText, displayGap } from "./prosody";
import { spokenPassage } from "../test/fixtures";
import { commitNotifications } from "./prosody";
import { createEntry } from "./editor";
import { defaultPreferences } from "./commands";
describe("speech analysis and presentation", () => {
  it("detects a voiced frequency and does not invent pitch in silence", () => {
    const signal = Float32Array.from(
      { length: 2048 },
      (_, index) => 0.2 * Math.sin((2 * Math.PI * 220 * index) / 16000),
    );
    expect(estimatePitch(signal)).toBeGreaterThan(215);
    expect(estimatePitch(signal)).toBeLessThan(225);
    expect(estimatePitch(new Float32Array(2048))).toBeUndefined();
    expect(powerDb(new Float32Array(100))).toBe(-160);
  });
  it("can speak punctuation explicitly without changing the stored entry", () => {
    const entry = { ...createEntry(), text: "Hello, world." };
    expect(
      presentedText(
        entry,
        { ...defaultPreferences, punctuation: true },
        { start: 0, end: 13 },
        true,
      ),
    ).toBe("Hello comma  world period ");
    expect(entry.text).toBe("Hello, world.");
  });
});

it("adds pause punctuation only after a grammatically complete phrase and spaces only after four seconds", () => {
  const gap = (text: string, pause: number) => {
    const passage = spokenPassage(text);
    const final = passage.spans.at(-1)!;
    const prior = passage.spans.at(-2)!;
    final.sourceStart = prior.sourceEnd + pause;
    final.sourceEnd = final.sourceStart + 0.3;
    const entry = { ...createEntry(), ...passage };
    return { entry, start: prior.end, end: final.start };
  };
  let example = gap("I bought a beautiful painting", 8);
  expect(
    displayGap(example.entry, example.start, example.end, defaultPreferences),
  ).toBe(" ");
  example = gap("it is beautiful outside", 8);
  expect(
    displayGap(example.entry, example.start, example.end, defaultPreferences),
  ).toBe(".\n\n");
  example = gap("hello friend", 3);
  const temporal = {
    ...defaultPreferences,
    punctuationSuggestions: false,
    temporalSuggestions: true,
  };
  expect(displayGap(example.entry, example.start, example.end, temporal)).toBe(
    " ",
  );
  example = gap("hello friend", 5);
  expect(displayGap(example.entry, example.start, example.end, temporal)).toBe(
    " ".repeat(10),
  );
});

it("preserves pause-based sentence and paragraph suggestions across recording chunks", () => {
  const entry = {
    ...createEntry(),
    text: "one two three",
    spans: [
      {
        start: 0,
        end: 3,
        clipId: "a",
        sourceStart: 0,
        sourceEnd: 1,
        rate: 1,
        gain: 1,
        recordingId: "session",
        recordedStart: 0,
        recordedEnd: 1,
      },
      {
        start: 4,
        end: 7,
        clipId: "b",
        sourceStart: 0,
        sourceEnd: 1,
        rate: 1,
        gain: 1,
        recordingId: "session",
        recordedStart: 5.5,
        recordedEnd: 6.5,
      },
      {
        start: 8,
        end: 13,
        clipId: "b",
        sourceStart: 9,
        sourceEnd: 10,
        rate: 1,
        gain: 1,
        recordingId: "session",
        recordedStart: 14.5,
        recordedEnd: 15.5,
      },
    ],
  };
  expect(presentedText(entry, defaultPreferences, { start: 0, end: 13 })).toBe(
    "one. Two.\n\nThree",
  );
  expect(
    presentedText(
      entry,
      { ...defaultPreferences, punctuationSuggestions: false },
      { start: 0, end: 13 },
    ),
  ).toBe(entry.text);
  expect(entry.text).toBe("one two three");
  expect(
    commitNotifications(entry, { start: 4, end: 13 }, defaultPreferences),
  ).toEqual(["New sentence", "New paragraph"]);
  expect(
    commitNotifications(entry, { start: 8, end: 13 }, defaultPreferences),
  ).toEqual(["New paragraph"]);
  expect(
    commitNotifications(
      entry,
      { start: 4, end: 13 },
      { ...defaultPreferences, punctuationSuggestions: false },
    ),
  ).toEqual([]);
  expect(presentedText(entry, defaultPreferences, { start: 8, end: 13 })).toBe(
    "Three",
  );
});

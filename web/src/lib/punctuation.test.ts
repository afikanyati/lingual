import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { createEntry, wordCount } from "./editor";
import { defaultPreferences, executeCommand, unitRanges } from "./commands";
import { Command } from "../enums/command";
import { insertPassage, copyPassage, transcriptPassage } from "./timeline";
import { playbackSlices } from "./timeline";
import { presentedText } from "./prosody";
import { spokenPassage } from "../test/fixtures";

const present = (text: string, pause = 5, suggestions = true, echo = false) => {
  const entry = insertPassage(createEntry(), spokenPassage(text));
  entry.spans = entry.spans.map((span, index) => ({
    ...span,
    sourceStart: index * (pause + 0.5),
    sourceEnd: index * (pause + 0.5) + 0.5,
  }));
  return presentedText(
    entry,
    {
      ...defaultPreferences,
      punctuationSuggestions: suggestions,
      punctuation: echo,
    },
    { start: 0, end: text.length },
    echo,
  );
};

describe("Whisper punctuation and native pause suggestions", () => {
  for (const text of [
    "Hello, world.",
    "Wait—really?",
    "Wait — really?",
    "Wait… really?",
    "“Finished.” Next",
    "Well; perhaps",
    "Done! Next",
    "Question? Yes",
  ]) {
    it(`keeps existing punctuation without duplicate pause marks: ${text}`, () => {
      expect(present(text)).toBe(text);
    });
  }
  it("uses native strict pause thresholds and adds paragraph endings only when missing", () => {
    expect(present("one two", 4)).toBe("one two");
    expect(present("one two", 4.01)).toBe("one. Two");
    expect(present("one two", 7)).toBe("one. Two");
    expect(present("one two", 7.01)).toBe("one.\n\nTwo");
    expect(present("Done. Next", 8)).toBe("Done.\n\nNext");
    expect(present("Wait— next", 8)).toBe("Wait— next");
  });
  it("uses comma suggestions before conjunctions rather than every two-second pause", () => {
    expect(present("one two", 3)).toBe("one two");
    expect(present("one and", 3)).toBe("one, and");
    expect(present("one and", 2)).toBe("one and");
  });
  it("echoes the original Swift punctuation names, plus Unicode quotes and ellipsis", () => {
    const source = readFileSync(
      "../diction-processor/data-structures/PunctuationMap.swift",
      "utf8",
    );
    for (const match of source.matchAll(/"([^"\n]+)": "([^"\n]+)"/g)) {
      const symbol = match[1] === "\\n" ? "\n" : match[1];
      expect(present(symbol, 0, true, true).trim()).toBe(match[2]);
    }
    expect(present("“Wait…”", 0, true, true)).toMatch(
      /open quote.*Wait.*ellipsis.*close quote/,
    );
  });
  it("does not read contractions, decimals, times or hyphenated words as punctuation", () => {
    expect(present("Don't re-enter at 3.14 or 12:30", 0, true, true)).toBe(
      "Don't re-enter at 3.14 or 12:30",
    );
  });
  it("does not count a standalone dash as a word, and separates words joined by an em dash", () => {
    expect(wordCount("Wait — really?")).toBe(2);
    expect(wordCount("Wait—really?")).toBe(2);
    expect(unitRanges("Wait—really?", "word")).toEqual([
      { start: 0, end: 4 },
      { start: 5, end: 12 },
    ]);
  });
  it("selects complete sentences with closing quotes, without splitting decimal numbers", () => {
    const text = "“It costs 3.14.” Really? Yes!";
    expect(
      unitRanges(text, "sentence").map((r) => text.slice(r.start, r.end)),
    ).toEqual(["“It costs 3.14.”", "Really?", "Yes!"]);
  });
  it("keeps inferred sentence selections mapped to the original word/audio offsets", () => {
    const entry = insertPassage(createEntry(), spokenPassage("one two"));
    entry.spans[1].sourceStart = 5;
    entry.spans[1].sourceEnd = 5.5;
    entry.selection = { start: 0, end: 0 };
    const outcome = executeCommand(Command.SELECT_SENTENCE, {
      entry,
      preferences: defaultPreferences,
      clipboard: { text: "", spans: [] },
    });
    expect(outcome.entry.selection).toEqual({ start: 0, end: 3 });
    expect(copyPassage(outcome.entry, outcome.entry.selection).text).toBe(
      "one",
    );
  });
  it("keeps zero-duration model punctuation as text, never invented audio intervals", () => {
    const passage = transcriptPassage(
      {
        text: "Wait — really?",
        words: [
          { text: "Wait", start: 0, end: 0.4 },
          { text: " —", start: 0.4, end: 0.4 },
          { text: " really?", start: 0.8, end: 1.2 },
        ],
      },
      "clip",
    );
    expect(passage.text).toBe("Wait — really?");
    expect(
      passage.spans.map((s) => [s.start, s.end, s.sourceStart, s.sourceEnd]),
    ).toEqual([
      [0, 4, 0, 0.4],
      [7, 14, 0.8, 1.2],
    ]);
  });
});

describe("punctuation preserves recorded editing units", () => {
  it("keeps a compound timestamp intact when selecting one side of an em dash", () => {
    const entry = insertPassage(
      createEntry(),
      transcriptPassage(
        {
          text: "Wait—really?",
          words: [{ text: "Wait—really?", start: 0.2, end: 1.4 }],
        },
        "clip",
      ),
    );
    const passage = copyPassage(entry, { start: 5, end: 11 });
    expect(passage.text).toBe("Wait—really?");
    expect(passage.spans).toMatchObject([{ sourceStart: 0.2, sourceEnd: 1.4 }]);
  });
  it("ignores positive-duration punctuation chunks without losing subsequent word offsets", () => {
    const passage = transcriptPassage(
      {
        text: "Wait — really?",
        words: [
          { text: "Wait", start: 0, end: 0.3 },
          { text: " —", start: 0.3, end: 0.5 },
          { text: " really?", start: 0.5, end: 1 },
        ],
      },
      "clip",
    );
    expect(passage.spans).toHaveLength(2);
    expect(passage.spans[1]).toMatchObject({
      start: 7,
      end: 14,
      sourceStart: 0.5,
    });
  });
  it("respects lowercase sentence endings while preserving common abbreviations", () => {
    const text = "Dr. Jones arrived. then we left. it cost 3.14.";
    expect(
      unitRanges(text, "sentence").map((range) =>
        text.slice(range.start, range.end),
      ),
    ).toEqual(["Dr. Jones arrived.", "then we left.", "it cost 3.14."]);
  });
});

it("retains the original pause across a punctuation-only model chunk", () => {
  const passage = transcriptPassage(
    {
      text: "Wait — really?",
      words: [
        { text: "Wait", start: 0, end: 0.3 },
        { text: " —", start: 0.3, end: 0.5 },
        { text: " really?", start: 0.8, end: 1 },
      ],
    },
    "clip",
  );
  const entry = insertPassage(createEntry(), passage);
  expect(
    playbackSlices(entry, { start: 0, end: entry.text.length }, false)[0].end,
  ).toBe(0.8);
  expect(
    playbackSlices(entry, { start: 0, end: entry.text.length }, true)[0].end,
  ).toBe(0.3);
});

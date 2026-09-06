import { describe, expect, it } from "vitest";
import { createEntry, replaceRange, undo } from "./editor";
import {
  insertPassage,
  copyPassage,
  transcriptPassage,
  playbackSlices,
} from "./timeline";
import { executeCommand } from "./commands";
import { Command } from "../enums/command";
import { spokenContext, spokenPassage } from "../test/fixtures";

describe("speech-only entry integrity", () => {
  it("rejects new words without a recording, including partially timed transcripts", () => {
    expect(() =>
      insertPassage(createEntry(), { text: "typed text", spans: [] }),
    ).toThrow(/recording/);
    const partial = spokenPassage("one two");
    partial.spans.pop();
    expect(() => insertPassage(createEntry(), partial)).toThrow(/recording/);
  });
  it("keeps the original intact when a replacement draft has no audio", () => {
    const context = spokenContext();
    const staged = executeCommand(Command.UPDATE_SELECTION, context);
    staged.replacement!.passage = { text: "typed draft", spans: [] };
    const result = executeCommand(Command.ACCEPT_SELECTION_UPDATE, staged);
    expect(result.entry).toBe(staged.entry);
    expect(result.replacement).toBeDefined();
    expect(result.message).toMatch(/recording/);
  });
  it("does not paste or cut a legacy unrecorded clipboard passage", () => {
    const context = spokenContext();
    context.clipboard = { text: "unrecorded", spans: [] };
    expect(executeCommand(Command.PASTE_CLIPBOARD, context).entry).toBe(
      context.entry,
    );
    context.entry = {
      ...context.entry,
      text: "legacy",
      spans: [],
      selection: { start: 0, end: 6 },
    };
    const result = executeCommand(Command.CUT_SELECTION, context);
    expect(result.entry).toBe(context.entry);
    expect(result.clipboard).toBe(context.clipboard);
  });
  it("selecting part of a spoken word copies its entire recorded segment", () => {
    const entry = insertPassage(createEntry(), spokenPassage("one two three"));
    const passage = copyPassage(entry, { start: 5, end: 6 });
    expect(passage.text).toBe("two");
    expect(passage.spans[0]).toMatchObject({
      start: 0,
      end: 3,
      sourceStart: 1,
      sourceEnd: 1.5,
    });
  });
  it("deleting inside a word never leaves untimed word fragments", () => {
    const entry = insertPassage(createEntry(), spokenPassage("one two three"));
    const changed = replaceRange(entry, 5, 6, "");
    expect(changed.text).toBe("one  three");
    expect(
      changed.spans.map((s) => changed.text.slice(s.start, s.end)),
    ).toEqual(["one", "three"]);
    expect(undo(changed).spans).toEqual(entry.spans);
  });
  it("inserting at the middle of a word moves after its recorded segment", () => {
    const entry = insertPassage(createEntry(), spokenPassage("one two"));
    const changed = insertPassage(
      { ...entry, selection: { start: 1, end: 1 } },
      spokenPassage("new", "new"),
    );
    expect(changed.text).toBe("one new two");
    expect(
      changed.spans.map((s) => changed.text.slice(s.start, s.end)),
    ).toEqual(["one", "new", "two"]);
  });
  it("rejects malformed source timings instead of inventing audio links", () => {
    const passage = spokenPassage("one");
    passage.spans[0].sourceEnd = 0;
    expect(() => insertPassage(createEntry(), passage)).toThrow(/recording/);
  });
  it("retains real word times for a repeated-word transcript", () => {
    const passage = transcriptPassage(
      {
        text: "one one",
        words: [
          { text: "one", start: 0, end: 0.4 },
          { text: "one", start: 0.7, end: 1 },
        ],
      },
      "clip",
    );
    const entry = insertPassage(createEntry(), passage);
    expect(entry.spans.map((s) => [s.start, s.sourceStart])).toEqual([
      [0, 0],
      [4, 0.7],
    ]);
  });
});

it("normalizes partial-word playback highlights to the whole recorded word", () => {
  const entry = insertPassage(createEntry(), spokenPassage("one two three"));
  expect(playbackSlices(entry, { start: 5, end: 6 }, true)[0]).toMatchObject({
    textStart: 4,
    textEnd: 7,
    start: 1,
    end: 1.5,
  });
});
for (const command of [Command.UNDO_CHANGE, Command.REDO_CHANGE]) {
  it(`does not resurrect unrecorded words through ${command}`, () => {
    const context = spokenContext();
    const invalid = {
      text: "legacy words",
      selection: { start: 0, end: 0 },
      spans: [],
    };
    if (command === Command.UNDO_CHANGE) context.entry.history = [invalid];
    else context.entry.future = [invalid];
    const result = executeCommand(command, context);
    expect(result.entry).toBe(context.entry);
    expect(result.message).toMatch(/recording/);
  });
}

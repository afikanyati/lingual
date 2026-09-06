import { describe, it, expect } from "vitest";
import {
  createEntry,
  undo,
  redo,
  selectionAt,
  wordCount,
  entryTitle,
} from "./editor";
import { insertPassage } from "./timeline";
import { executeCommand, parseCommand, defaultPreferences } from "./commands";
import { Command } from "../enums/command";
import { spokenPassage, spokenContext } from "../test/fixtures";

describe("recorded entry editing", () => {
  it("restores both recorded words and their source audio through undo and redo", () => {
    const first = insertPassage(createEntry(), spokenPassage("Hello world"));
    const changed = insertPassage(
      { ...first, selection: { start: 6, end: 11 } },
      spokenPassage("Lingual", "replacement"),
    );
    expect(undo(changed).text).toBe("Hello world");
    expect(undo(changed).spans).toEqual(first.spans);
    expect(undo(undo(changed)).text).toBe("");
    expect(redo(undo(changed)).spans).toEqual(changed.spans);
    expect(changed.text).toBe("Hello Lingual");
  });
  it("does not lose incoming speech when the user undoes and dictates again", () => {
    let entry = insertPassage(createEntry(), spokenPassage("One"));
    entry = insertPassage(entry, spokenPassage("two"));
    entry = insertPassage(undo(entry), spokenPassage("three"));
    expect(entry.text).toBe("One three");
    expect(redo(entry).text).toBe("One three");
  });
  it("adds spaces around inserted speech without disturbing punctuation", () => {
    const entry = insertPassage(createEntry(), spokenPassage("Hello world."));
    const changed = insertPassage(
      { ...entry, selection: { start: 6, end: 6 } },
      spokenPassage("beautiful"),
    );
    expect(changed.text).toBe("Hello beautiful world.");
    expect(
      changed.spans.map((span) => changed.text.slice(span.start, span.end)),
    ).toEqual(["Hello", "beautiful", "world."]);
  });
  it("only recognizes whole utterance commands", () => {
    expect(parseCommand("Delete entry.", spokenContext())).toBe(
      Command.DELETE_ENTRY,
    );
    expect(
      parseCommand("I might delete entry later", spokenContext()),
    ).toBeUndefined();
  });
  it("deletes selected words and restores their audio on undo", () => {
    const entry = {
      ...insertPassage(createEntry(), spokenPassage("red green blue")),
      selection: { start: 4, end: 10 },
    };
    const result = executeCommand(Command.DELETE_SELECTION, {
      entry,
      preferences: defaultPreferences,
      clipboard: { text: "", spans: [] },
    }).entry;
    expect(result.text).toBe("red blue");
    expect(undo(result).spans).toEqual(entry.spans);
  });
  it("does not cut or delete without a selection", () => {
    const context = spokenContext();
    context.entry.selection = { start: 0, end: 0 };
    expect(executeCommand(Command.CUT_SELECTION, context).entry).toBe(
      context.entry,
    );
    expect(executeCommand(Command.DELETE_SELECTION, context).entry).toBe(
      context.entry,
    );
  });
  it("uses the creation date as a title and preserves older saved titles", () => {
    const entry = createEntry();
    expect(entryTitle(entry)).toContain(
      new Date(entry.createdAt).toLocaleDateString(),
    );
    expect(entryTitle({ ...entry, title: "Older title" })).toBe("Older title");
  });
  it("counts words and clamps selection boundaries", () => {
    expect(wordCount("  one\n two  ")).toBe(2);
    expect(selectionAt("Hello", -4, 999)).toEqual({ start: 0, end: 5 });
  });
});

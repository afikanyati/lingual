import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { Command } from "../enums/command";
import {
  commandCatalog,
  defaultPreferences,
  executeCommand,
  parseCommand,
} from "./commands";
import { createEntry } from "./editor";
import { insertPassage } from "./timeline";
import { spokenPassage } from "../test/fixtures";
import type { CommandContext } from "../interfaces/workspace";
const context = (): CommandContext => ({
  entry: {
    ...insertPassage(
      createEntry(),
      spokenPassage("One small thought. Another sentence.\n\nA paragraph."),
    ),
    selection: { start: 4, end: 9 },
    lastCommit: { start: 0, end: 17 },
  },
  preferences: { ...defaultPreferences },
  clipboard: spokenPassage("test", "clipboard"),
});

describe("native feature catalog", () => {
  it("starts a new recorded entry while resume explicitly targets the selected entry", () => {
    const current = context();
    expect(executeCommand(Command.START_ENTRY, current).effect).toEqual({
      kind: "new-entry",
      startRecording: true,
    });
    expect(executeCommand(Command.RESUME_ENTRY, current).effect).toEqual({
      kind: "listen",
    });
    expect(executeCommand(Command.CREATE_ENTRY, current).effect).toEqual({
      kind: "new-entry",
    });
    expect(executeCommand(Command.START_ENTRY, current).entry).toBe(
      current.entry,
    );
  });
  it("covers every active native enum case", () => {
    const swift = readFileSync(
      "../diction-processor/VoiceCommandEngine.swift",
      "utf8",
    ).replace(/\/\/[^\n]*/g, "");
    const section = swift
      .split("public enum VoiceCommand:")[1]
      .split("func value()")[0];
    const cases = [...section.matchAll(/case (\w+) =/g)]
      .map((match) => match[1])
      .sort();
    expect(commandCatalog.map((command) => command.id).sort()).toEqual(cases);
  });
  for (const command of commandCatalog) {
    it(`resolves and executes ${command.id}`, () => {
      expect(parseCommand(command.label, context())).toBe(command.id);
      const result = executeCommand(command.id, context());
      expect(result.command).toBe(command.id);
      expect(result.message.length).toBeGreaterThan(0);
    });
  }
  it("keeps original aliases but does not execute a command buried in dictation", () => {
    expect(parseCommand("freeze entry", context())).toBe(Command.PAUSE_ENTRY);
    expect(parseCommand("open dictionary", context())).toBe(
      Command.ENTER_DICTIONARY,
    );
    expect(
      parseCommand("I might delete entry later", context()),
    ).toBeUndefined();
    expect(parseCommand("literal delete entry", context())).toBeUndefined();
  });
  it("supports staged replacement without destroying the original before acceptance", () => {
    const first = executeCommand(Command.UPDATE_SELECTION, context());
    expect(first.entry.text).toBe(context().entry.text);
    first.replacement!.passage = spokenPassage("lovely", "replacement");
    expect(
      executeCommand(Command.CANCEL_SELECTION_UPDATE, first).entry.text,
    ).toBe(context().entry.text);
    expect(
      executeCommand(Command.ACCEPT_SELECTION_UPDATE, first).entry.text,
    ).toContain("One lovely thought.");
  });
  it("expands and moves selection at word boundaries without escaping the entry", () => {
    const expanded = executeCommand(Command.EXPAND_SELECTION, context());
    expect(
      expanded.entry.text.slice(
        expanded.entry.selection.start,
        expanded.entry.selection.end,
      ),
    ).toBe("One small thought.");
    const shifted = executeCommand(Command.SHIFT_SELECTION_FORWARD, context());
    expect(
      shifted.entry.text.slice(
        shifted.entry.selection.start,
        shifted.entry.selection.end,
      ),
    ).toBe("thought.");
  });
  it("selects sentence and paragraph without deleting either", () => {
    const sentence = executeCommand(Command.SELECT_SENTENCE, context()).entry;
    expect(
      sentence.text.slice(sentence.selection.start, sentence.selection.end),
    ).toBe("One small thought.");
    expect(sentence.text).toBe(context().entry.text);
  });
  it("starts, steps and pauses a word run while preserving its range", () => {
    let result = executeCommand(Command.RUN_ENTRY, context());
    expect(result.browse?.ranges).toHaveLength(7);
    result = executeCommand(Command.SHIFT_NEXT_WALK_ELEMENT, result);
    expect(result.browse?.index).toBe(1);
    expect(executeCommand(Command.PAUSE_RUN, result).browse).toMatchObject({
      mode: "walk",
      paused: false,
      index: 1,
    });
  });
});

it("maps directional and selection-speed aliases to the intended action", () => {
  expect(parseCommand("skip playback forward", context())).toBe(
    Command.SKIP_PLAYBACK_FORWARD,
  );
  expect(parseCommand("skip playback next", context())).toBe(
    Command.SKIP_PLAYBACK_FORWARD,
  );
  expect(parseCommand("skip playback previous", context())).toBe(
    Command.SKIP_PLAYBACK_BACKWARD,
  );
  expect(parseCommand("adjust up selection rate", context())).toBe(
    Command.INCREASE_SELECTION_RATE,
  );
});

it("recognizes the user's play note wording without consuming ordinary speech", () => {
  expect(parseCommand("play note")).toBe(Command.PLAY_ENTRY);
  expect(parseCommand("play note is what I said yesterday")).toBeUndefined();
});

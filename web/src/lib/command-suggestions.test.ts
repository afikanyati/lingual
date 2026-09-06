import { describe, expect, it } from "vitest";
import { Command } from "../enums/command";
import { createEntry } from "./editor";
import { defaultPreferences, parseCommand } from "./commands";
import {
  commandSuggestions,
  selectionSuggestions,
} from "./command-suggestions";
import type { CommandContext } from "../interfaces/workspace";
import { spokenPassage } from "../test/fixtures";
import { insertPassage } from "./timeline";

function context(): CommandContext {
  return {
    entry: insertPassage(createEntry(), spokenPassage("One small thought.")),
    preferences: { ...defaultPreferences },
    clipboard: { text: "", spans: [] },
  };
}

describe("contextual command discovery", () => {
  it("offers useful selection actions without requiring speech or modifying the entry", () => {
    const state = context();
    expect(selectionSuggestions(state)).toEqual([]);
    state.entry.selection = { start: 4, end: 9 };
    const before = structuredClone(state.entry);
    expect(selectionSuggestions(state).map((item) => item.id)).toEqual([
      Command.PLAY_SELECTION,
      Command.UPDATE_SELECTION,
      Command.COPY_SELECTION,
      Command.DELETE_SELECTION,
      Command.REMOVE_SELECTION,
    ]);
    expect(state.entry).toEqual(before);
    for (const action of selectionSuggestions(state))
      expect(parseCommand(action.label, state)).toBe(action.id);
  });
  it("hides selection suggestions during dialogs, replacement, or automatic browsing", () => {
    const state = context();
    state.entry.selection = { start: 4, end: 9 };
    expect(selectionSuggestions({ ...state, dialog: "help" })).toEqual([]);
    expect(
      selectionSuggestions({
        ...state,
        replacement: {
          range: state.entry.selection,
          passage: spokenPassage("new"),
        },
      }),
    ).toEqual([]);
    expect(
      selectionSuggestions({
        ...state,
        browse: {
          mode: "walk",
          scope: "selection",
          ranges: [state.entry.selection],
          index: 0,
          paused: false,
        },
      }),
    ).toEqual([]);
  });
  it("does not suggest playback or copying when selected words have no recording", () => {
    const state = context();
    state.entry.selection = { start: 4, end: 9 };
    state.entry.spans = [];
    expect(selectionSuggestions(state).map((item) => item.id)).toEqual([
      Command.UPDATE_SELECTION,
      Command.DELETE_SELECTION,
      Command.REMOVE_SELECTION,
    ]);
  });
  it("completes words with the heard prefix separate from the unspoken suffix", () => {
    const suggestions = commandSuggestions("START", context());
    expect(suggestions).toContainEqual({
      id: Command.START_ENTRY,
      heard: "start",
      remaining: "entry",
    });
    expect(suggestions).toContainEqual({
      id: Command.START_ECHO,
      heard: "start",
      remaining: "echo",
    });
    expect(
      commandSuggestions("activate punctuation", context()),
    ).toContainEqual({
      id: Command.ACTIVATE_PUNCTUATION_SUGGESTIONS,
      heard: "activate punctuation",
      remaining: "suggestions",
    });
  });
  it("matches whole utterance prefixes, never command fragments buried in prose", () => {
    for (const text of [
      "",
      "sta",
      "I should start",
      "start thinking about it",
      "don't play",
      "play entry tomorrow",
    ])
      expect(commandSuggestions(text, context())).toEqual([]);
  });
  it("retains recognized aliases and punctuation without inventing executable commands", () => {
    for (const text of [
      "begin",
      "play note",
      "START,",
      "please start",
      "enter entry",
    ]) {
      const matches = commandSuggestions(text, context());
      expect(matches.length).toBeGreaterThan(0);
      for (const match of matches)
        expect(
          parseCommand(`${match.heard} ${match.remaining}`, context()),
        ).toBe(match.id);
    }
  });
  it("limits selection, history, clipboard, playback, and browse actions to available context", () => {
    const state = context();
    expect(
      commandSuggestions("play", state).map((item) => item.id),
    ).not.toContain(Command.PLAY_SELECTION);
    state.entry.selection = { start: 0, end: 3 };
    expect(commandSuggestions("play", state).map((item) => item.id)).toContain(
      Command.PLAY_SELECTION,
    );
    expect(
      commandSuggestions("resume", state).map((item) => item.id),
    ).not.toContain(Command.RESUME_PLAYBACK);
    state.playback = "audio";
    expect(
      commandSuggestions("resume", state).map((item) => item.id),
    ).toContain(Command.RESUME_PLAYBACK);
    expect(commandSuggestions("paste", state)).toEqual([]);
    state.clipboard = spokenPassage("Copied");
    expect(commandSuggestions("paste", state)).toHaveLength(1);
    state.entry.future = [];
    expect(commandSuggestions("redo", state)).toEqual([]);
  });
  it("filters empty entry suggestions and keeps starting and creating available", () => {
    const state = { ...context(), entry: createEntry() };
    expect(commandSuggestions("play", state)).toEqual([]);
    expect(commandSuggestions("start", state).map((item) => item.id)).toContain(
      Command.START_ENTRY,
    );
    expect(
      commandSuggestions("create", state).map((item) => item.id),
    ).toContain(Command.CREATE_ENTRY);
  });
  it("restricts dialog and replacement choices", () => {
    const state = context();
    state.dialog = "delete";
    expect(commandSuggestions("start", state)).toEqual([]);
    expect(commandSuggestions("cancel", state).map((item) => item.id)).toEqual([
      Command.CANCEL_DIALOG,
    ]);
    state.dialog = "export";
    expect(commandSuggestions("export", state).map((item) => item.id)).toEqual([
      Command.EXPORT_AUDIO,
      Command.EXPORT_TEXT,
    ]);
    state.dialog = null;
    state.replacement = {
      range: { start: 0, end: 3 },
      passage: spokenPassage("New"),
    };
    expect(commandSuggestions("play", state)).toEqual([]);
    expect(commandSuggestions("accept", state).map((item) => item.id)).toEqual([
      Command.ACCEPT_SELECTION_UPDATE,
    ]);
  });
});

import { expect, it } from "vitest";
import { Command } from "../enums/command";
import { executeCommand, defaultPreferences, parseCommand } from "./commands";
import { createEntry, replaceRange, undo } from "./editor";
import { insertPassage } from "./timeline";
import { spokenPassage } from "../test/fixtures";
import type { CommandContext } from "../interfaces/workspace";
const context = (
  text = "First sentence. Second longer sentence.\n\nThird paragraph.",
): CommandContext => ({
  entry: {
    ...insertPassage(createEntry(), spokenPassage(text)),
    selection: { start: 0, end: 0 },
  },
  preferences: { ...defaultPreferences },
  clipboard: { text: "", spans: [] },
});
it("infers playback, echo and dialog objects and accepts the native polite command example", () => {
  expect(parseCommand("pause", { ...context(), playback: "audio" })).toBe(
    Command.PAUSE_PLAYBACK,
  );
  expect(parseCommand("stop", { ...context(), playback: "echo" })).toBe(
    Command.STOP_ECHO,
  );
  expect(parseCommand("cancel", { ...context(), dialog: "delete" })).toBe(
    Command.CANCEL_DIALOG,
  );
  expect(parseCommand("delete", { ...context(), dialog: "delete" })).toBe(
    Command.CONTINUE_DIALOG,
  );
  expect(parseCommand("please start an entry", context())).toBe(
    Command.START_ENTRY,
  );
  expect(
    parseCommand("please do not delete an entry", context()),
  ).toBeUndefined();
});
it("dialog and replacement choices cannot execute unrelated destructive actions", () => {
  const dialog = { ...context(), dialog: "delete" as const };
  expect(executeCommand(Command.DELETE_SELECTION, dialog).entry).toEqual(
    dialog.entry,
  );
  expect(executeCommand(Command.DELETE_ENTRY, dialog).effect?.kind).toBe(
    "confirm-dialog",
  );
  const replacing = executeCommand(Command.UPDATE_SELECTION, {
    ...context(),
    entry: { ...context().entry, selection: { start: 0, end: 5 } },
  });
  expect(
    executeCommand(Command.CREATE_ENTRY, replacing).effect,
  ).toBeUndefined();
  expect(
    executeCommand(Command.STOP_ENTRY, { ...context(), playback: "audio" })
      .effect?.kind,
  ).toBe("stop-playback");
});
it("retains sentence and paragraph scale through next/previous and clears before the selected sentence", () => {
  let state = executeCommand(Command.SELECT_SENTENCE, context());
  state = executeCommand(Command.SHIFT_SELECTION_FORWARD, state);
  expect(
    state.entry.text.slice(
      state.entry.selection.start,
      state.entry.selection.end,
    ),
  ).toBe("Second longer sentence.");
  state = executeCommand(Command.SHIFT_SELECTION_BACKWARD, state);
  expect(
    state.entry.text.slice(
      state.entry.selection.start,
      state.entry.selection.end,
    ),
  ).toBe("First sentence.");
  state = executeCommand(Command.REMOVE_SELECTION, state);
  expect(state.entry.selection).toEqual({ start: 0, end: 0 });
  state = executeCommand(Command.SELECT_PARAGRAPH, context());
  state = executeCommand(Command.SHIFT_SELECTION_FORWARD, state);
  expect(
    state.entry.text.slice(
      state.entry.selection.start,
      state.entry.selection.end,
    ),
  ).toBe("Third paragraph.");
  state = executeCommand(Command.SHIFT_SELECTION_FORWARD, state);
  expect(
    state.entry.text.slice(
      state.entry.selection.start,
      state.entry.selection.end,
    ),
  ).toBe("Third paragraph.");
});
it("pause run becomes a walk of the same word; deleting that word exits browsing", () => {
  let state = executeCommand(Command.RUN_ENTRY, context("one two three"));
  state = executeCommand(Command.SHIFT_NEXT_WALK_ELEMENT, state);
  state.entry.selection = state.browse!.ranges[1];
  state = executeCommand(Command.PAUSE_RUN, state);
  expect(state.browse).toMatchObject({ index: 1, mode: "walk", paused: false });
  expect(state.effect?.kind).toBe("browse");
  state = executeCommand(Command.DELETE_SELECTION, state);
  expect(state.entry.text).not.toContain("two");
  expect(state.browse).toBeUndefined();
  expect(state.effect?.kind).toBe("stop-playback");
});
it("uses native ten-second skips", () => {
  expect(
    executeCommand(Command.SKIP_PLAYBACK_FORWARD, context()).effect?.offset,
  ).toBe(10);
  expect(
    executeCommand(Command.SKIP_PLAYBACK_BACKWARD, context()).effect?.offset,
  ).toBe(-10);
});
it("pastes after the selection anchor without deleting the selected speech or creating a dictation commit", () => {
  const state = context("one two three");
  state.entry.selection = { start: 4, end: 13 };
  state.clipboard = spokenPassage("copied", "copy");
  const pasted = executeCommand(Command.PASTE_CLIPBOARD, state).entry;
  expect(pasted.text).toBe("one two copied three");
  expect(pasted.commits).toHaveLength(state.entry.commits!.length);
  expect(undo(pasted).selection).toEqual(state.entry.selection);
});
it("removing the latest commit exposes the previous surviving commit, including after insertion before it and undo", () => {
  let entry = insertPassage(createEntry(), spokenPassage("first phrase", "a"));
  entry = insertPassage(entry, spokenPassage("second phrase", "b"));
  entry = replaceRange(
    entry,
    entry.lastCommit!.start,
    entry.lastCommit!.end,
    "",
  );
  expect(entry.text.slice(entry.lastCommit!.start, entry.lastCommit!.end)).toBe(
    "first phrase",
  );
  const restored = undo(entry);
  expect(
    restored.text.slice(restored.lastCommit!.start, restored.lastCommit!.end),
  ).toBe("second phrase");
  const inserted = insertPassage(
    { ...restored, selection: { start: 0, end: 0 } },
    spokenPassage("prefix", "c"),
  );
  const removed = replaceRange(inserted, 0, 6, "");
  expect(
    removed.text.slice(removed.lastCommit!.start, removed.lastCommit!.end),
  ).toBe("second phrase");
});
it("accepting/canceling a replacement restores a paused run with fresh ranges", () => {
  let state = executeCommand(Command.RUN_ENTRY, context("one two three"));
  state.entry.selection = { start: 4, end: 7 };
  state = executeCommand(Command.UPDATE_SELECTION, state);
  state.replacement!.passage = spokenPassage("many new words", "replacement");
  state = executeCommand(Command.ACCEPT_SELECTION_UPDATE, state);
  expect(state.browse).toMatchObject({ mode: "run", paused: false });
  expect(
    state.browse!.ranges.map((range) =>
      state.entry.text.slice(range.start, range.end),
    ),
  ).toEqual(["one", "many", "new", "words", "three"]);
  expect(state.effect?.kind).toBe("browse");
  state = executeCommand(Command.UPDATE_SELECTION, state);
  state = executeCommand(Command.CANCEL_SELECTION_UPDATE, state);
  expect(state.browse?.paused).toBe(false);
});

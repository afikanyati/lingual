import { describe, expect, it } from "vitest";
import { Command } from "../enums/command";
import { executeCommand, parseCommand, unitRanges } from "./commands";
import { createEntry, replaceRange, undo, redo } from "./editor";
import {
  applySpanRate,
  copyPassage,
  insertPassage,
  playbackSlices,
} from "./timeline";
import { spokenContext, spokenPassage } from "../test/fixtures";
import type { CommandContext } from "../interfaces/workspace";

const selectedText = (context: CommandContext) =>
  context.entry.text.slice(
    context.entry.selection.start,
    context.entry.selection.end,
  );
const run = (command: Command, context = spokenContext()) =>
  executeCommand(command, context);

describe("Lingual Tests to Specify: cursor and immutable audio", () => {
  it("LTS-001 LTS-005 LTS-012 LTS-147 keeps the caret after inserted speech, including mid-entry", () => {
    let entry = insertPassage(createEntry(), spokenPassage("one three"));
    expect(entry.selection).toEqual({ start: 9, end: 9 });
    entry = insertPassage(
      { ...entry, selection: { start: 4, end: 4 } },
      spokenPassage("two", "inserted"),
    );
    expect(entry.text).toBe("one two three");
    expect(entry.selection).toEqual({ start: 8, end: 8 });
    expect(
      playbackSlices(entry, { start: 0, end: 13 }, true).map((s) => [
        s.clipId,
        s.start,
      ]),
    ).toEqual([
      ["original", 0],
      ["inserted", 0],
      ["original", 1],
    ]);
  });
  it("LTS-015 LTS-067 LTS-068 copies from the front to the back without duplicate audio or changing originals", () => {
    const original = spokenContext().entry;
    const clipboard = copyPassage(original, { start: 0, end: 7 });
    const result = insertPassage(
      {
        ...original,
        selection: { start: original.text.length, end: original.text.length },
      },
      clipboard,
    );
    expect(result.text).toBe(original.text + " one two");
    expect(result.selection.start).toBe(result.text.length);
    expect(result.spans.slice(-2).map((s) => s.sourceStart)).toEqual([0, 1]);
    expect(original.spans).toHaveLength(8);
    expect(clipboard.spans[0].start).toBe(0);
  });
  it("LTS-071 LTS-072 replaces identical words with new audio once and remains undoable", () => {
    const before = {
      ...spokenContext().entry,
      selection: { start: 4, end: 7 },
    };
    const changed = insertPassage(before, spokenPassage("two", "replacement"));
    expect(changed.spans).toHaveLength(8);
    expect(changed.spans[1].clipId).toBe("replacement");
    expect(changed.selection).toEqual({ start: 7, end: 7 });
    expect(undo(changed).spans).toEqual(before.spans);
  });
  it("LTS-068 empty clipboard is a true no-op, including selection and undo history", () => {
    const before = spokenContext().entry;
    expect(insertPassage(before, { text: "", spans: [] })).toBe(before);
  });
  it("LTS-041 LTS-069 deletes at the beginning of the removed passage and reset returns to zero", () => {
    const result = run(Command.DELETE_SELECTION);
    expect(result.entry.text).toBe("one  five six seven eight");
    expect(result.entry.selection).toEqual({ start: 4, end: 4 });
    expect(
      replaceRange(result.entry, 0, result.entry.text.length, "").selection,
    ).toEqual({ start: 0, end: 0 });
  });
  it("LTS-020 LTS-056 LTS-108 keeps the most recent commit range through undo and redo", () => {
    const before = spokenContext().entry;
    const added = insertPassage(
      { ...before, selection: { start: 0, end: 0 } },
      spokenPassage("new", "new"),
    );
    expect(added.lastCommit).toEqual({ start: 0, end: 3 });
    expect(
      run(Command.SELECT_COMMIT, { ...spokenContext(), entry: added }).entry
        .selection,
    ).toEqual(added.lastCommit);
    expect(undo(added).lastCommit).toEqual(before.lastCommit);
    expect(redo(undo(added)).lastCommit).toEqual(added.lastCommit);
  });
});

describe("LTS-049 through LTS-055 overlapping selection speed transformations", () => {
  const cases = [
    ["LTS-050", [2, 5], [3, 4]],
    ["LTS-051", [2, 5], [2, 5]],
    ["LTS-052", [3, 4], [2, 5]],
    ["LTS-053", [2, 5], [0, 3]],
    ["LTS-054", [2, 5], [5, 7]],
  ] as const;
  for (const [id, first, second] of cases) {
    for (const delta of [0.2, -0.2]) {
      it(`${id} preserves exactly the affected words for delta ${delta}`, () => {
        const entry = spokenContext().entry;
        const range = (indices: readonly number[]) => ({
          start: entry.spans[indices[0]].start,
          end: entry.spans[indices[1]].end,
        });
        const changed = applySpanRate(
          applySpanRate(entry, range(first), delta),
          range(second),
          delta,
        );
        const expected = entry.spans.map((_, index) =>
          Number(
            (
              1 +
              (index >= first[0] && index <= first[1] ? delta : 0) +
              (index >= second[0] && index <= second[1] ? delta : 0)
            ).toFixed(2),
          ),
        );
        expect(changed.spans.map((s) => s.rate)).toEqual(expected);
        expect(
          playbackSlices(
            changed,
            { start: 0, end: changed.text.length },
            true,
          ).map((s) => s.rate),
        ).toEqual(expected);
        expect(undo(undo(changed)).spans).toEqual(entry.spans);
        expect(entry.spans.every((s) => s.rate === 1)).toBe(true);
      });
    }
  }
  it("LTS-055 clamps repeated increases/decreases and does not affect unselected words", () => {
    let context = spokenContext();
    for (let i = 0; i < 30; i++)
      context = run(Command.INCREASE_SELECTION_RATE, context);
    expect(context.entry.spans.map((s) => s.rate)).toEqual([
      1, 3, 3, 3, 1, 1, 1, 1,
    ]);
    for (let i = 0; i < 30; i++)
      context = run(Command.DECREASE_SELECTION_RATE, context);
    expect(context.entry.spans.map((s) => s.rate)).toEqual([
      1, 0.2, 0.2, 0.2, 1, 1, 1, 1,
    ]);
  });
});

describe("Lingual voice commands have observable outcomes", () => {
  const effects: [string, Command, string, string][] = [
    ["LTS-075 LTS-087", Command.PLAY_SELECTION, "play", "selection"],
    ["LTS-076 LTS-087", Command.ECHO_SELECTION, "echo", "selection"],
    ["LTS-013 LTS-083 LTS-085", Command.PLAY_ENTRY, "play", "entry"],
    ["LTS-084", Command.ECHO_ENTRY, "echo", "entry"],
    ["LTS-106", Command.PLAY_COMMIT, "play", "commit"],
    ["LTS-107", Command.ECHO_COMMIT, "echo", "commit"],
    ["LTS-062 LTS-150", Command.EXPORT_AUDIO, "export", "selection"],
    ["LTS-062 LTS-151", Command.EXPORT_TEXT, "export", "selection"],
  ];
  for (const [id, command, kind, scope] of effects)
    it(`${id} ${command} retains selection and targets the correct range`, () => {
      const context = spokenContext();
      const result = run(command, context);
      expect(result.entry).toBe(context.entry);
      expect(result.effect).toMatchObject({
        kind,
        range:
          scope === "selection"
            ? context.entry.selection
            : scope === "commit"
              ? context.entry.lastCommit
              : { start: 0, end: context.entry.text.length },
      });
    });
  it("LTS-036 LTS-037 selects and plays/echoes only the last sentence", () => {
    const context = {
      ...spokenContext(),
      entry: insertPassage(
        createEntry(),
        spokenPassage("First sentence. Last sentence!"),
      ),
    };
    const selected = run(Command.SELECT_SENTENCE, context);
    expect(selectedText(selected)).toBe("Last sentence!");
    for (const command of [Command.PLAY_SELECTION, Command.ECHO_SELECTION])
      expect(run(command, selected).effect).toMatchObject({
        range: { start: 16, end: 30 },
      });
  });
  for (const [id, command, kind] of [
    ["LTS-030", Command.PAUSE_PLAYBACK, "pause-playback"],
    ["LTS-032 LTS-039", Command.STOP_ENTRY, "stop-listening"],
    ["LTS-034", Command.PAUSE_ECHO, "pause-echo"],
    ["LTS-148", Command.START_ENTRY, "new-entry"],
    ["LTS-152", Command.CANCEL_DIALOG, "close-dialog"],
    ["LTS-152", Command.CONTINUE_DIALOG, "confirm-dialog"],
  ] as const)
    it(`${id} ${command} requests ${kind} without editing`, () => {
      const context = spokenContext();
      const result = run(command, context);
      expect(result.effect).toEqual(
        command === Command.START_ENTRY
          ? { kind, startRecording: true }
          : { kind },
      );
      expect(result.entry).toBe(context.entry);
    });
  it("LTS-065 skips in both directions", () => {
    expect(run(Command.SKIP_PLAYBACK_BACKWARD).effect).toEqual({
      kind: "seek",
      offset: -10,
    });
    expect(run(Command.SKIP_PLAYBACK_FORWARD).effect).toEqual({
      kind: "seek",
      offset: 10,
    });
  });
  it("LTS-046 LTS-099 copies exact audio without editing the entry", () => {
    const before = spokenContext();
    const result = run(Command.COPY_SELECTION, before);
    expect(result.entry).toBe(before.entry);
    expect(result.clipboard.text).toBe("two three four");
    expect(result.clipboard.spans.map((s) => s.sourceStart)).toEqual([1, 2, 3]);
  });
  it("LTS-047 LTS-100 cuts text and audio together", () => {
    const result = run(Command.CUT_SELECTION);
    expect(result.clipboard.text).toBe("two three four");
    expect(result.entry.spans.map((s) => s.sourceStart)).toEqual([
      0, 4, 5, 6, 7,
    ]);
    expect(result.entry.selection).toEqual({ start: 4, end: 4 });
  });
  it("LTS-048 LTS-103 pastes clipboard audio at the selected location", () => {
    const result = run(Command.PASTE_CLIPBOARD);
    // SelectionCursor.pasteClipboard inserts after its anchor, keeping the selected audio.
    expect(result.entry.text).toBe(
      "one two new words three four five six seven eight",
    );
    expect(result.entry.spans.slice(2, 4).map((s) => s.clipId)).toEqual([
      "clipboard",
      "clipboard",
    ]);
    expect(result.entry.selection).toEqual({ start: 17, end: 17 });
  });
  it("LTS-066 LTS-110 previews the clipboard without replacing the entry", () => {
    const context = spokenContext();
    const result = run(Command.INSPECT_CLIPBOARD, context);
    expect(result.effect).toEqual({ kind: "play", passage: context.clipboard });
    expect(result.entry).toBe(context.entry);
  });
  it("LTS-092 LTS-182 clears at the end of the selection and later dictation inserts there", () => {
    const cleared = run(Command.REMOVE_SELECTION);
    expect(cleared.entry.selection).toEqual({ start: 18, end: 18 });
    expect(insertPassage(cleared.entry, spokenPassage("new")).text).toBe(
      "one two three four new five six seven eight",
    );
  });
  it("LTS-093 LTS-109 deletes the correct selection or commit", () => {
    expect(
      run(Command.DELETE_SELECTION).entry.spans.map((s) => s.ordinal),
    ).toEqual([0, 4, 5, 6, 7]);
    const context = spokenContext();
    context.entry.lastCommit = { start: 4, end: 18 };
    expect(run(Command.ROLLBACK_COMMIT, context).entry.text).toBe(
      "one  five six seven eight",
    );
  });
  const shifts: [string, Command, string][] = [
    ["LTS-104", Command.EXPAND_SELECTION, "one two three four five"],
    ["LTS-105", Command.REDUCE_SELECTION, "three"],
    ["LTS-111", Command.SHIFT_ANCHOR_RIGHT, "three four"],
    ["LTS-112", Command.SHIFT_ANCHOR_LEFT, "one two three four"],
    ["LTS-113", Command.SHIFT_FOCUS_LEFT, "two three"],
    ["LTS-114", Command.SHIFT_FOCUS_RIGHT, "two three four five"],
    ["LTS-115", Command.SHIFT_SELECTION_BACKWARD, "one two three"],
    ["LTS-116", Command.SHIFT_SELECTION_FORWARD, "three four five"],
  ];
  for (const [id, command, expected] of shifts)
    it(`${id} ${command} moves whole-word boundaries`, () =>
      expect(selectedText(run(command))).toBe(expected));
  for (const command of shifts.map((row) => row[1]))
    it(`${command} remains bounded after repeated movement at either edge`, () => {
      let context = spokenContext();
      for (let index = 0; index < 30; index++) context = run(command, context);
      expect(context.entry.selection.start).toBeGreaterThanOrEqual(0);
      expect(context.entry.selection.end).toBeLessThanOrEqual(
        context.entry.text.length,
      );
      expect(context.entry.selection.end).toBeGreaterThan(
        context.entry.selection.start,
      );
    });
  for (const [id, command, expected] of [
    ["LTS-091 LTS-175", Command.SELECT_WORD, "two"],
    [
      "LTS-174",
      Command.SELECT_SENTENCE,
      "one two three four five six seven eight",
    ],
    [
      "LTS-173",
      Command.SELECT_PARAGRAPH,
      "one two three four five six seven eight",
    ],
  ] as const)
    it(`${id} ${command} preserves text`, () => {
      const context = spokenContext();
      const result = run(command, context);
      expect(selectedText(result)).toBe(expected);
      expect(result.entry.text).toBe(context.entry.text);
    });
});

describe("LTS-071 LTS-094 staged replacement", () => {
  for (const hasSpeech of [false, true])
    it(`LTS-074 LTS-097 LTS-098 cancels ${hasSpeech ? "after" : "before"} replacement speech`, () => {
      const context = spokenContext();
      const staged = run(Command.UPDATE_SELECTION, context);
      if (hasSpeech)
        staged.replacement!.passage = spokenPassage("replacement", "new");
      const result = run(Command.CANCEL_SELECTION_UPDATE, staged);
      expect(result.entry).toBe(context.entry);
      expect(result.replacement).toBeUndefined();
    });
  it("LTS-073 LTS-096 redo clears the draft and keeps its original target", () => {
    const staged = run(Command.UPDATE_SELECTION);
    staged.replacement!.passage = spokenPassage("replacement");
    const result = run(Command.REDO_SELECTION_UPDATE, staged);
    expect(result.replacement).toEqual({
      range: { start: 4, end: 18 },
      passage: { text: "", spans: [] },
    });
    expect(result.entry).toBe(staged.entry);
  });
  it("LTS-072 LTS-095 accepts text and its new audio atomically", () => {
    const staged = run(Command.UPDATE_SELECTION);
    staged.replacement!.passage = spokenPassage("replacement", "new");
    const result = run(Command.ACCEPT_SELECTION_UPDATE, staged);
    expect(result.entry.text).toBe("one replacement five six seven eight");
    expect(result.entry.spans[1].clipId).toBe("new");
    expect(result.replacement).toBeUndefined();
  });
  it("empty acceptance preserves the original and keeps the draft open", () => {
    const staged = run(Command.UPDATE_SELECTION);
    const result = run(Command.ACCEPT_SELECTION_UPDATE, staged);
    expect(result.entry).toBe(staged.entry);
    expect(result.replacement).toBeDefined();
  });
  for (const word of ["accept", "redo", "cancel"])
    it(`${word} shorthand targets replacement only while a draft is open`, () => {
      expect(parseCommand(word, run(Command.UPDATE_SELECTION))).toBe(
        {
          accept: Command.ACCEPT_SELECTION_UPDATE,
          redo: Command.REDO_SELECTION_UPDATE,
          cancel: Command.CANCEL_SELECTION_UPDATE,
        }[word],
      );
    });
});

describe("Lingual walk/run transitions", () => {
  for (const [id, command, mode, scope, length] of [
    ["LTS-117", Command.WALK_SELECTION, "walk", "selection", 3],
    ["LTS-118", Command.WALK_ENTRY, "walk", "entry", 8],
    ["LTS-120", Command.WALK_COMMIT, "walk", "commit", 8],
    ["LTS-125", Command.RUN_SELECTION, "run", "selection", 3],
    ["LTS-126", Command.RUN_ENTRY, "run", "entry", 8],
    ["LTS-128", Command.RUN_COMMIT, "run", "commit", 8],
  ] as const)
    it(`${id} ${command} starts at the first word of the right scope`, () => {
      const result = run(command);
      expect(result.browse).toMatchObject({
        mode,
        scope,
        index: 0,
        paused: false,
      });
      expect(result.browse!.ranges).toHaveLength(length);
      expect(result.effect).toEqual({ kind: "browse" });
    });
  it("LTS-121 LTS-122 previous/next remain in the current passage", () => {
    let context = run(Command.WALK_SELECTION);
    context = run(Command.SHIFT_PREVIOUS_WALK_ELEMENT, context);
    expect(context.browse!.index).toBe(0);
    for (let i = 0; i < 10; i++)
      context = run(Command.SHIFT_NEXT_WALK_ELEMENT, context);
    expect(context.browse!.index).toBe(2);
  });
  for (const command of [Command.WALK_SELECTION, Command.RUN_SELECTION])
    it(`LTS-077 LTS-078 ${command} pauses before staging replacement`, () => {
      const result = run(Command.UPDATE_SELECTION, run(command));
      expect(result.browse!.paused).toBe(true);
      expect(result.effect).toEqual({ kind: "stop-playback" });
      expect(result.replacement!.range).toEqual({ start: 4, end: 18 });
    });
  it("LTS-081 LTS-131 exiting walk inserts new speech after the selected segment", () => {
    const result = run(Command.EXIT_WALK, run(Command.WALK_SELECTION));
    expect(result.browse).toBeUndefined();
    expect(result.entry.selection).toEqual({ start: 18, end: 18 });
    expect(insertPassage(result.entry, spokenPassage("new")).text).toBe(
      "one two three four new five six seven eight",
    );
  });
  it("LTS-129 halts without losing the current word index", () => {
    const current = run(
      Command.SHIFT_NEXT_WALK_ELEMENT,
      run(Command.RUN_ENTRY),
    );
    expect(run(Command.PAUSE_RUN, current).browse).toEqual({
      ...current.browse,
      mode: "walk",
      paused: false,
    });
  });
});

describe("LTS-133 contextual abbreviated commands", () => {
  for (const [id, phrase, expected] of [
    ["LTS-134", "delete", Command.DELETE_SELECTION],
    ["LTS-135", "replace", Command.UPDATE_SELECTION],
    ["LTS-136", "copy", Command.COPY_SELECTION],
    ["LTS-137", "cut", Command.CUT_SELECTION],
    ["LTS-138", "export", Command.EXPORT_SELECTION],
    ["LTS-139", "run", Command.RUN_SELECTION],
    ["LTS-140", "walk", Command.WALK_SELECTION],
    ["LTS-145", "reduce", Command.REDUCE_SELECTION],
    ["LTS-146", "expand", Command.EXPAND_SELECTION],
    ["LTS-101", "increase selection rate", Command.INCREASE_SELECTION_RATE],
    ["LTS-102", "decrease selection rate", Command.DECREASE_SELECTION_RATE],
  ] as const)
    it(`${id} '${phrase}' operates on the current selection`, () =>
      expect(parseCommand(phrase, spokenContext())).toBe(expected));
  for (const phrase of ["freeze", "halt", "stop run", "pause run"])
    it(`LTS-141 LTS-142 LTS-143 LTS-144 '${phrase}' pauses an active run`, () => {
      expect(parseCommand(phrase, run(Command.RUN_ENTRY))).toBe(
        Command.PAUSE_RUN,
      );
    });
  it("LTS-082 bare stop outside a mode is not a recording command", () => {
    const context = spokenContext();
    context.entry.selection = { start: 0, end: 0 };
    expect(parseCommand("stop", context)).toBeUndefined();
  });
});

describe("LTS-161 through LTS-171 undo restores caret, text and audio", () => {
  for (const [id, command] of [
    ["LTS-165", Command.INCREASE_SELECTION_RATE],
    ["LTS-166", Command.DECREASE_SELECTION_RATE],
    ["LTS-167", Command.DELETE_SELECTION],
    ["LTS-168", Command.CUT_SELECTION],
    ["LTS-170", Command.PASTE_CLIPBOARD],
    ["LTS-171", Command.ROLLBACK_COMMIT],
  ] as const)
    it(`${id} undo and redo after ${command}`, () => {
      const before = spokenContext();
      const edited = run(command, before);
      const undone = run(Command.UNDO_CHANGE, edited);
      for (const key of ["text", "selection", "spans", "lastCommit"] as const)
        expect(undone.entry[key]).toEqual(before.entry[key]);
      const redone = run(Command.REDO_CHANGE, undone);
      for (const key of ["text", "selection", "spans", "lastCommit"] as const)
        expect(redone.entry[key]).toEqual(edited.entry[key]);
    });
  it("LTS-162 LTS-164 undo restores speech and accepted replacement including the selection", () => {
    const before = spokenContext();
    const staged = run(Command.UPDATE_SELECTION, before);
    staged.replacement!.passage = spokenPassage("new", "new");
    const accepted = run(Command.ACCEPT_SELECTION_UPDATE, staged);
    expect(undo(accepted.entry).spans).toEqual(before.entry.spans);
    expect(undo(accepted.entry).selection).toEqual(before.entry.selection);
    const spoken = insertPassage(before.entry, spokenPassage("new", "new"));
    expect(undo(spoken).text).toBe(before.entry.text);
  });
  it("LTS-172 handles 10,000 words with valid paragraph/sentence ranges and bounded undo", () => {
    let entry = insertPassage(
      createEntry(),
      spokenPassage(
        Array.from(
          { length: 1000 },
          () => "one two three four five. six seven eight nine ten!\n\n",
        ).join(""),
      ),
    );
    expect(unitRanges(entry.text, "word")).toHaveLength(10000);
    expect(unitRanges(entry.text, "sentence")).toHaveLength(2000);
    expect(unitRanges(entry.text, "paragraph")).toHaveLength(1000);
    for (let index = 0; index < 105; index++)
      entry = insertPassage(entry, spokenPassage("word"));
    expect(entry.history).toHaveLength(100);
    expect(entry.selection.start).toBe(entry.text.length);
  });
});

it("LTS-183 entering an entry cancels its list browsing state", () => {
  expect(
    run(Command.ENTER_ENTRY, run(Command.WALK_ENTRY_LIST)).browse,
  ).toBeUndefined();
});

it("LTS-094 accepts the spoken replace selection alias without treating ordinary sentences as commands", () => {
  expect(parseCommand("replace selection", spokenContext())).toBe(
    Command.UPDATE_SELECTION,
  );
  expect(
    parseCommand("literal replace selection", spokenContext()),
  ).toBeUndefined();
  expect(
    parseCommand("I will replace selection later", spokenContext()),
  ).toBeUndefined();
});

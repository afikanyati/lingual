import { SelectionScale } from "../enums/selection";
import { spokenWordRanges, sentenceRanges } from "./punctuation";
import { presentedUnitRanges } from "./prosody";
import { Command } from "../enums/command";
import catalog from "./native-commands.json";
import type {
  CommandContext,
  CommandEffect,
  CommandOutcome,
  Preferences,
  CommandDescription,
} from "../interfaces/workspace";
import type { TextSelection } from "../interfaces/entry";
import {
  copyPassage,
  insertPassage,
  pastePassage,
  applySpanRate,
} from "./timeline";
import { redo, replaceRange, undo } from "./editor";
import { hasCompleteAudio, recordedSelection } from "./audio-integrity";

export const defaultPreferences: Preferences = {
  punctuation: true,
  omitSilences: true,
  temporalSuggestions: false,
  punctuationSuggestions: true,
  formattingSuggestions: true,
  passiveEcho: true,
  capitalization: true,
  voiceFeedback: true,
  voiceURI: "",
  volume: 1,
  echoRate: 1,
  playbackRate: 1,
};
export const commandCatalog = catalog.commands as CommandDescription[];
// The user calls entries "notes" too; keep this alias outside the generated Swift catalog.
export const commandAliases: Record<string, string> = {
  ...catalog.aliases,
  note: "ENTRY",
};

/** Match complete utterances, while retaining the original action/object aliases and contextual shorthand. */
export function parseCommand(
  input: string,
  context?: CommandContext,
): Command | undefined {
  const normalized = input
    .toLowerCase()
    .trim()
    .replace(/^[“”"‘’]+|[\p{P}]+$/gu, "")
    .trim();
  if (
    context?.dialog &&
    ["cancel", "dismiss", "continue", "accept", "delete"].includes(normalized)
  ) {
    if (["cancel", "dismiss"].includes(normalized))
      return Command.CANCEL_DIALOG;
    if (normalized !== "delete" || context.dialog === "delete")
      return Command.CONTINUE_DIALOG;
  }
  if (
    context?.playback &&
    ["pause", "freeze", "stop", "resume", "continue"].includes(normalized)
  ) {
    const echo = context.playback === "echo";
    if (normalized === "stop")
      return echo ? Command.STOP_ECHO : Command.STOP_PLAYBACK;
    if (["resume", "continue"].includes(normalized))
      return echo ? Command.RESUME_ECHO : Command.RESUME_PLAYBACK;
    return echo ? Command.PAUSE_ECHO : Command.PAUSE_PLAYBACK;
  }
  const exact = commandCatalog.find((item) => item.label === normalized);
  if (exact) return exact.id;
  const shortcuts: Record<string, Command> = {
    undo: Command.UNDO_CHANGE,
    redo: Command.REDO_CHANGE,
    paste: Command.PASTE_CLIPBOARD,
    "stop listening": Command.STOP_ENTRY,
    "reveal actions": Command.ENTER_DICTIONARY,
    next: Command.SHIFT_NEXT_WALK_ELEMENT,
    previous: Command.SHIFT_PREVIOUS_WALK_ELEMENT,
    "clear selection": Command.REMOVE_SELECTION,
    "replace selection": Command.UPDATE_SELECTION,
  };
  if (context?.replacement && ["accept", "cancel", "redo"].includes(normalized))
    return {
      accept: Command.ACCEPT_SELECTION_UPDATE,
      cancel: Command.CANCEL_SELECTION_UPDATE,
      redo: Command.REDO_SELECTION_UPDATE,
    }[normalized];
  if (shortcuts[normalized]) return shortcuts[normalized];
  // Bare stop is reserved for a browsing mode; dictation uses the explicit "stop entry" command.
  if (normalized === "stop" && !context?.browse) return;
  if (
    context?.browse &&
    ["freeze", "halt", "stop", "pause"].includes(normalized)
  )
    return Command.PAUSE_RUN;
  if (
    normalized === "replace" &&
    context &&
    context.entry.selection.start < context.entry.selection.end
  )
    return Command.UPDATE_SELECTION;
  // Native documentation permits polite articles; negation and other prose must never be discarded.
  const words = normalized
    .split(/\s+/)
    .filter((word) => !["please", "a", "an", "the"].includes(word));
  const tokens: string[] = [];
  for (let index = 0; index < words.length; ) {
    const pair = words.slice(index, index + 2).join(" ");
    if (commandAliases[pair]) {
      tokens.push(commandAliases[pair]);
      index += 2;
      continue;
    }
    if (!commandAliases[words[index]]) return; // Ordinary speech containing command words is still speech.
    tokens.push(commandAliases[words[index]]);
    index++;
  }
  const sets = [tokens];
  if (context?.entry.selection.start !== context?.entry.selection.end)
    sets.push([...tokens, "SELECTION"]);
  if (context?.browse) sets.push([...tokens, "WALK"]);
  sets.push([...tokens, "ENTRY"]);
  for (const possible of sets) {
    const rules = catalog.grammar.filter(
      (rule) =>
        rule.tokens.length === new Set(possible).size &&
        rule.tokens.every((token) => possible.includes(token)),
    );
    if (rules.length === 1) return rules[0].command as Command;
  }
}
export function unitRanges(
  text: string,
  unit: "word" | "sentence" | "paragraph",
): TextSelection[] {
  if (unit === "word") return spokenWordRanges(text);
  if (unit === "sentence") return sentenceRanges(text);
  const expression = /[^\n]+(?:\n(?!\n)[^\n]+)*/g;
  return [...text.matchAll(expression)]
    .map((match) => ({
      start: match.index! + (match[0].match(/^\s*/)?.[0].length ?? 0),
      end: match.index! + match[0].trimEnd().length,
    }))
    .filter((range) => range.end > range.start);
}
function selectUnit(
  text: string,
  caret: number,
  unit: "word" | "sentence" | "paragraph",
  context?: CommandContext,
): TextSelection {
  const ranges =
    context && unit !== "word"
      ? presentedUnitRanges(context.entry, context.preferences, unit)
      : unitRanges(text, unit);
  return (
    ranges.find((range) => range.end > caret) ??
    ranges.at(-1) ?? { start: 0, end: 0 }
  );
}
const fullRange = (context: CommandContext) => ({
  start: 0,
  end: context.entry.text.length,
});
const bounded = (value: number, minimum: number, maximum: number) =>
  Math.max(minimum, Math.min(maximum, Math.round(value * 100) / 100));

/** Every native command resolves to a state transition or a concrete playback/navigation effect. */
export function executeCommand(
  command: Command,
  context: CommandContext,
): CommandOutcome {
  const aligned = recordedSelection(
    context.entry.text,
    context.entry.selection,
    context.entry.spans,
  );
  let entry =
    aligned.start === context.entry.selection.start &&
    aligned.end === context.entry.selection.end
      ? context.entry
      : { ...context.entry, selection: aligned };
  let preferences = { ...context.preferences };
  let clipboard = context.clipboard;
  let replacement = context.replacement;
  let browse = context.browse;
  let effect: CommandEffect | undefined;
  let message =
    commandCatalog.find((item) => item.id === command)?.label ?? command;
  if (context.dialog === "delete" && command === Command.DELETE_ENTRY)
    return {
      ...context,
      command,
      effect: { kind: "confirm-dialog" },
      message: "Delete entry",
    };
  const dialogChoices =
    context.dialog === "export"
      ? [Command.EXPORT_AUDIO, Command.EXPORT_TEXT, Command.CANCEL_DIALOG]
      : [Command.CONTINUE_DIALOG, Command.CANCEL_DIALOG];
  if (
    ["delete", "export"].includes(context.dialog ?? "") &&
    !dialogChoices.includes(command)
  )
    return {
      ...context,
      command,
      message: "Choose one of the actions in this dialog, or say cancel.",
    };
  if (
    replacement &&
    ![
      Command.ACCEPT_SELECTION_UPDATE,
      Command.REDO_SELECTION_UPDATE,
      Command.CANCEL_SELECTION_UPDATE,
    ].includes(command)
  )
    return {
      ...context,
      command,
      message: "Say accept, redo, or cancel for this replacement.",
    };
  const selected = entry.selection.end > entry.selection.start;
  const selectionRequired =
    /_SELECTION$|^SHIFT_(ANCHOR|FOCUS)|^ACCEPT_SELECTION|^REDO_SELECTION|^CANCEL_SELECTION/.test(
      command,
    ) && ![Command.ENTER_SELECTION, Command.REMOVE_SELECTION].includes(command);
  if (selectionRequired && !selected && !replacement)
    return { ...context, command, message: "Select some text first." };
  const range = command.includes("COMMIT")
    ? (entry.lastCommit ?? { start: entry.text.length, end: entry.text.length })
    : command.includes("SELECTION")
      ? entry.selection
      : fullRange(context);
  const transferred = [Command.COPY_SELECTION, Command.CUT_SELECTION].includes(
    command,
  )
    ? copyPassage(entry, entry.selection)
    : command === Command.PASTE_CLIPBOARD
      ? clipboard
      : command === Command.ACCEPT_SELECTION_UPDATE
        ? replacement?.passage
        : command === Command.UNDO_CHANGE
          ? entry.history.at(-1)
          : command === Command.REDO_CHANGE
            ? entry.future.at(-1)
            : undefined;
  if (transferred && !hasCompleteAudio(transferred))
    return {
      ...context,
      command,
      message:
        "This passage has words without a recording. Speak a replacement or retry the saved audio.",
    };
  switch (command) {
    case Command.PLAY_ENTRY:
    case Command.PLAY_SELECTION:
    case Command.PLAY_COMMIT:
      effect = { kind: "play", range };
      break;
    case Command.ECHO_ENTRY:
    case Command.ECHO_SELECTION:
    case Command.ECHO_COMMIT:
    case Command.START_ECHO:
    case Command.PLAY_ECHO:
      effect = { kind: "echo", range };
      break;
    case Command.START_ENTRY:
      effect = { kind: "new-entry", startRecording: true };
      break;
    case Command.RESUME_ENTRY:
    case Command.EDIT_ENTRY:
      effect = { kind: "listen" };
      break;
    case Command.CREATE_ENTRY:
      effect = { kind: "new-entry" };
      break;
    case Command.PAUSE_ENTRY:
      effect = {
        kind:
          context.playback === "audio" ? "pause-playback" : "stop-listening",
      };
      break;
    case Command.STOP_ENTRY:
      effect = {
        kind: context.playback === "audio" ? "stop-playback" : "stop-listening",
      };
      break;
    case Command.DELETE_ENTRY:
      effect = { kind: "delete-entry" };
      break;
    case Command.ENTER_ENTRY_LIST:
      effect = { kind: "library" };
      break;
    case Command.ENTER_ENTRY:
      browse = undefined;
      effect = { kind: "open-entry" };
      break;
    case Command.PAUSE_ECHO:
      effect = { kind: "pause-echo" };
      break;
    case Command.RESUME_ECHO:
      effect = { kind: "resume-echo" };
      break;
    case Command.STOP_ECHO:
      effect = { kind: "stop-echo" };
      break;
    case Command.PAUSE_PLAYBACK:
      effect = { kind: "pause-playback" };
      break;
    case Command.RESUME_PLAYBACK:
      effect = { kind: "resume-playback" };
      break;
    case Command.STOP_PLAYBACK:
      effect = { kind: "stop-playback" };
      break;
    case Command.SKIP_PLAYBACK_BACKWARD:
      effect = { kind: "seek", offset: -10 };
      break;
    case Command.SKIP_PLAYBACK_FORWARD:
      effect = { kind: "seek", offset: 10 };
      break;
    case Command.ACTIVATE_PUNCTUATION:
      preferences.punctuation = true;
      break;
    case Command.DEACTIVATE_PUNCTUATION:
      preferences.punctuation = false;
      break;
    case Command.ACTIVATE_SILENCES:
      preferences.omitSilences = false;
      break;
    case Command.DEACTIVATE_SILENCES:
      preferences.omitSilences = true;
      break;
    case Command.ACTIVATE_TEMPORAL_SUGGESTIONS:
      preferences.temporalSuggestions = true;
      break;
    case Command.DEACTIVATE_TEMPORAL_SUGGESTIONS:
      preferences.temporalSuggestions = false;
      break;
    case Command.ACTIVATE_PUNCTUATION_SUGGESTIONS:
      preferences.punctuationSuggestions = true;
      break;
    case Command.DEACTIVATE_PUNCTUATION_SUGGESTIONS:
      preferences.punctuationSuggestions = false;
      break;
    case Command.ACTIVATE_FORMATTING_SUGGESTIONS:
      preferences.formattingSuggestions = true;
      break;
    case Command.DEACTIVATE_FORMATTING_SUGGESTIONS:
      preferences.formattingSuggestions = false;
      break;
    case Command.ACTIVATE_PASSIVE_ECHO:
      preferences.passiveEcho = true;
      break;
    case Command.DEACTIVATE_PASSIVE_ECHO:
      preferences.passiveEcho = false;
      break;
    case Command.INCREASE_VOLUME:
      preferences.volume = bounded(preferences.volume + 0.2, 0.1, 1);
      break;
    case Command.DECREASE_VOLUME:
      preferences.volume = bounded(preferences.volume - 0.2, 0.1, 1);
      break;
    case Command.INCREASE_ECHO_RATE:
      preferences.echoRate = bounded(preferences.echoRate + 0.1, 0.1, 3);
      break;
    case Command.DECREASE_ECHO_RATE:
      preferences.echoRate = bounded(preferences.echoRate - 0.1, 0.1, 3);
      break;
    case Command.INCREASE_PLAYBACK_RATE:
      preferences.playbackRate = bounded(
        preferences.playbackRate + 0.2,
        0.2,
        3,
      );
      break;
    case Command.DECREASE_PLAYBACK_RATE:
      preferences.playbackRate = bounded(
        preferences.playbackRate - 0.2,
        0.2,
        3,
      );
      break;
    case Command.INCREASE_SELECTION_RATE:
      entry = applySpanRate(entry, entry.selection, 0.2);
      break;
    case Command.DECREASE_SELECTION_RATE:
      entry = applySpanRate(entry, entry.selection, -0.2);
      break;
    case Command.COPY_SELECTION:
      clipboard = copyPassage(entry, entry.selection);
      break;
    case Command.CUT_SELECTION:
      clipboard = copyPassage(entry, entry.selection);
      entry = replaceRange(
        entry,
        entry.selection.start,
        entry.selection.end,
        "",
      );
      break;
    case Command.DELETE_SELECTION:
      entry = replaceRange(
        entry,
        entry.selection.start,
        entry.selection.end,
        "",
      );
      break;
    case Command.PASTE_CLIPBOARD:
      entry = pastePassage(entry, clipboard);
      break;
    case Command.INSPECT_CLIPBOARD:
      effect = { kind: "play", passage: clipboard };
      break;
    case Command.REMOVE_SELECTION:
      entry = {
        ...entry,
        selection: {
          start:
            entry.selectionScale &&
            entry.selectionScale !== SelectionScale.Word &&
            entry.selection.end < entry.text.length
              ? entry.selection.start
              : entry.selection.end,
          end:
            entry.selectionScale &&
            entry.selectionScale !== SelectionScale.Word &&
            entry.selection.end < entry.text.length
              ? entry.selection.start
              : entry.selection.end,
        },
        selectionScale: undefined,
      };
      break;
    case Command.ENTER_SELECTION:
    case Command.SELECT_WORD:
      entry = {
        ...entry,
        selection: selectUnit(entry.text, entry.selection.start, "word"),
        selectionScale: SelectionScale.Word,
      };
      break;
    case Command.SELECT_SENTENCE:
      entry = {
        ...entry,
        selectionScale: SelectionScale.Sentence,
        selection: selectUnit(entry.text, entry.selection.start, "sentence", {
          ...context,
          entry,
        }),
      };
      break;
    case Command.SELECT_PARAGRAPH:
      entry = {
        ...entry,
        selectionScale: SelectionScale.Paragraph,
        selection: selectUnit(entry.text, entry.selection.start, "paragraph", {
          ...context,
          entry,
        }),
      };
      break;
    case Command.SELECT_COMMIT:
      entry = { ...entry, selection: range };
      break;
    case Command.ROLLBACK_COMMIT:
      entry = replaceRange(entry, range.start, range.end, "");
      break;
    case Command.EXPAND_SELECTION:
    case Command.REDUCE_SELECTION:
    case Command.SHIFT_ANCHOR_LEFT:
    case Command.SHIFT_ANCHOR_RIGHT:
    case Command.SHIFT_FOCUS_LEFT:
    case Command.SHIFT_FOCUS_RIGHT:
    case Command.SHIFT_SELECTION_BACKWARD:
    case Command.SHIFT_SELECTION_FORWARD: {
      const scale = entry.selectionScale;
      if (
        [
          Command.SHIFT_SELECTION_FORWARD,
          Command.SHIFT_SELECTION_BACKWARD,
        ].includes(command) &&
        scale &&
        scale !== SelectionScale.Word
      ) {
        const units = presentedUnitRanges(entry, preferences, scale);
        const current = units.findIndex(
          (unit) => unit.end > entry.selection.start,
        );
        const direction = command === Command.SHIFT_SELECTION_FORWARD ? 1 : -1;
        const next = units[current + direction];
        if (next) entry = { ...entry, selection: next };
        else
          message =
            direction > 0 ? "At end of entry." : "At beginning of entry.";
        break;
      }
      const words = unitRanges(entry.text, "word");
      if (!words.length) break;
      let first = Math.max(
        0,
        words.findIndex((word) => word.end > entry.selection.start),
      );
      let last = words.findIndex((word) => word.end >= entry.selection.end);
      if (last < 0) last = words.length - 1;
      if (command === Command.EXPAND_SELECTION) {
        first--;
        last++;
      }
      if (command === Command.REDUCE_SELECTION) {
        if (last - first >= 2) {
          first++;
          last--;
        }
      }
      if (
        [Command.SHIFT_ANCHOR_LEFT, Command.SHIFT_SELECTION_BACKWARD].includes(
          command,
        )
      )
        first--;
      if (
        [Command.SHIFT_ANCHOR_RIGHT, Command.SHIFT_SELECTION_FORWARD].includes(
          command,
        )
      )
        first++;
      if (
        [Command.SHIFT_FOCUS_LEFT, Command.SHIFT_SELECTION_BACKWARD].includes(
          command,
        )
      )
        last--;
      if (
        [Command.SHIFT_FOCUS_RIGHT, Command.SHIFT_SELECTION_FORWARD].includes(
          command,
        )
      )
        last++;
      first = bounded(first, 0, words.length - 1);
      last = bounded(last, first, words.length - 1);
      entry = {
        ...entry,
        selection: { start: words[first].start, end: words[last].end },
      };
      break;
    }
    case Command.UPDATE_SELECTION:
      // Freeze the selected word(s) before collecting a draft so a run cannot move the target.
      if (browse) {
        browse = { ...browse, paused: true };
        effect = { kind: "stop-playback" };
      }
      replacement = {
        range: { ...entry.selection },
        passage: { text: "", spans: [] },
      };
      message = "Speak a replacement, then accept, redo, or cancel.";
      break;
    case Command.ACCEPT_SELECTION_UPDATE:
      if (replacement?.passage.text) {
        entry = insertPassage(
          { ...entry, selection: replacement.range },
          replacement.passage,
        );
        replacement = undefined;
      } else message = "Speak a replacement first.";
      break;
    case Command.REDO_SELECTION_UPDATE:
      if (replacement)
        replacement = { ...replacement, passage: { text: "", spans: [] } };
      break;
    case Command.CANCEL_SELECTION_UPDATE:
      replacement = undefined;
      break;
    case Command.WALK_ENTRY:
    case Command.RUN_ENTRY:
    case Command.WALK_SELECTION:
    case Command.RUN_SELECTION:
    case Command.WALK_COMMIT:
    case Command.RUN_COMMIT:
    case Command.WALK_ENTRY_LIST:
    case Command.RUN_ENTRY_LIST: {
      const scope = command.includes("LIST")
        ? "list"
        : command.includes("SELECTION")
          ? "selection"
          : command.includes("COMMIT")
            ? "commit"
            : "entry";
      const ranges = unitRanges(entry.text, "word").filter(
        (word) => word.start >= range.start && word.end <= range.end,
      );
      browse = {
        scope,
        mode: command.startsWith("RUN") ? "run" : "walk",
        ranges,
        index: 0,
        paused: false,
      };
      effect = { kind: "browse" };
      break;
    }
    case Command.SHIFT_NEXT_WALK_ELEMENT:
    case Command.SHIFT_PREVIOUS_WALK_ELEMENT:
      if (browse) {
        browse = {
          ...browse,
          index: bounded(
            browse.index +
              (command === Command.SHIFT_NEXT_WALK_ELEMENT ? 1 : -1),
            0,
            browse.scope === "list"
              ? Number.MAX_SAFE_INTEGER
              : Math.max(0, browse.ranges.length - 1),
          ),
        };
        effect = { kind: "browse" };
      } else
        message = "Start walking an entry, selection, or entry list first.";
      break;
    case Command.PAUSE_RUN:
      if (browse) {
        browse = { ...browse, mode: "walk", paused: false };
        effect = { kind: "browse" };
        message = "Run paused to walk.";
      }
      break;
    case Command.EXIT_WALK:
      if (browse && browse.scope !== "list")
        entry = {
          ...entry,
          selection: { start: entry.selection.end, end: entry.selection.end },
        };
      browse = undefined;
      effect = { kind: "stop-playback" };
      break;
    case Command.EXPORT_ENTRY:
    case Command.EXPORT_SELECTION:
      effect = { kind: "export", range, format: "choose" };
      break;
    case Command.EXPORT_AUDIO:
      effect = {
        kind: "export",
        range: selected ? entry.selection : fullRange(context),
        format: "audio",
      };
      break;
    case Command.EXPORT_TEXT:
      effect = {
        kind: "export",
        range: selected ? entry.selection : fullRange(context),
        format: "text",
      };
      break;
    case Command.UNDO_CHANGE:
      entry = undo(entry);
      break;
    case Command.REDO_CHANGE:
      entry = redo(entry);
      break;
    case Command.ENTER_DICTIONARY:
      effect = { kind: "help" };
      break;
    case Command.EXIT_DICTIONARY:
    case Command.CANCEL_DIALOG:
      effect = { kind: "close-dialog" };
      break;
    case Command.CONTINUE_DIALOG:
      effect = { kind: "confirm-dialog" };
      break;
    case Command.GRANT_PERMISSION:
      effect = { kind: "permissions" };
      break;
    default: {
      const exhaustive: never = command;
      throw new Error(`Unimplemented command: ${exhaustive}`);
    }
  }
  // Native replacement confirmation resumes the paused browse; other text edits exit it.
  if (
    browse &&
    [Command.ACCEPT_SELECTION_UPDATE, Command.CANCEL_SELECTION_UPDATE].includes(
      command,
    ) &&
    context.replacement &&
    !replacement
  ) {
    const oldStart = browse.ranges[0]?.start ?? 0;
    const oldEnd = browse.ranges.at(-1)?.end ?? entry.text.length;
    const delta = entry.text.length - context.entry.text.length;
    const ranges = unitRanges(entry.text, "word").filter(
      (word) =>
        browse!.scope === "entry" ||
        (word.start >= oldStart && word.end <= oldEnd + delta),
    );
    const position =
      command === Command.ACCEPT_SELECTION_UPDATE
        ? Math.max(0, entry.selection.end - 1)
        : context.replacement.range.start;
    const index = Math.max(
      0,
      ranges.findIndex((word) => word.end > position),
    );
    browse = ranges.length
      ? { ...browse, ranges, index, paused: false }
      : undefined;
    if (browse)
      entry = {
        ...entry,
        selection: ranges[index],
        selectionScale: SelectionScale.Word,
      };
    effect = { kind: browse ? "browse" : "stop-playback" };
  } else if (browse && entry.text !== context.entry.text) {
    browse = undefined;
    effect = { kind: "stop-playback" };
  }
  return {
    entry,
    preferences,
    clipboard,
    replacement,
    browse,
    command,
    effect,
    message,
  };
}

import { Command } from "../enums/command";
import type {
  CommandSuggestion,
  CommandSuggestionContext,
  CommonCommand,
} from "../interfaces/command-suggestions";
import { commandAliases, commandCatalog, parseCommand } from "./commands";
import { hasCompleteAudio } from "./audio-integrity";
import { copyPassage } from "./timeline";
const replacementCommands = [
  Command.ACCEPT_SELECTION_UPDATE,
  Command.REDO_SELECTION_UPDATE,
  Command.CANCEL_SELECTION_UPDATE,
];
const exportCommands = [
  Command.EXPORT_AUDIO,
  Command.EXPORT_TEXT,
  Command.CANCEL_DIALOG,
];
const dialogCommands = [Command.CONTINUE_DIALOG, Command.CANCEL_DIALOG];

/** Offer actions only when their target exists. This is discovery, never dispatch. */
function available(id: Command, context: CommandSuggestionContext): boolean {
  const { entry, dialog, replacement, playback, browse } = context;
  if (dialog === "delete") return dialogCommands.includes(id);
  if (dialog === "export") return exportCommands.includes(id);
  if (replacement) return replacementCommands.includes(id);
  if (replacementCommands.includes(id)) return false;
  if (dialogCommands.includes(id) || id === Command.EXIT_DICTIONARY)
    return Boolean(dialog);
  if (id === Command.GRANT_PERMISSION) return false;
  if (id.includes("PLAYBACK")) return playback === "audio";
  if ([Command.PAUSE_ECHO, Command.STOP_ECHO, Command.RESUME_ECHO].includes(id))
    return playback === "echo";
  if ([Command.PAUSE_ENTRY, Command.STOP_ENTRY].includes(id))
    return Boolean(context.listening || playback === "audio");
  if (
    [
      Command.PAUSE_RUN,
      Command.EXIT_WALK,
      Command.SHIFT_NEXT_WALK_ELEMENT,
      Command.SHIFT_PREVIOUS_WALK_ELEMENT,
    ].includes(id)
  )
    return Boolean(browse);
  if (id === Command.UNDO_CHANGE) return entry.history.length > 0;
  if (id === Command.REDO_CHANGE) return entry.future.length > 0;
  if ([Command.PASTE_CLIPBOARD, Command.INSPECT_CLIPBOARD].includes(id))
    return Boolean(context.clipboard.text);
  if (id.includes("COMMIT"))
    return Boolean(
      entry.lastCommit && entry.lastCommit.end > entry.lastCommit.start,
    );
  if (
    (id.includes("SELECTION") && id !== Command.ENTER_SELECTION) ||
    /^SHIFT_(ANCHOR|FOCUS)/.test(id)
  )
    return entry.selection.end > entry.selection.start;
  if (
    /^(PLAY|ECHO|WALK|RUN|EXPORT|SELECT)_/.test(id) ||
    [Command.START_ECHO, Command.ENTER_SELECTION].includes(id)
  )
    return Boolean(entry.text);
  return true;
}

/** Tokenize native multiword aliases without mistaking a fragment of prose for a command. */
function tokens(text: string): string[] {
  const words = text
    .split(" ")
    .filter((word) => !["please", "a", "an", "the"].includes(word));
  const result: string[] = [];
  for (let index = 0; index < words.length; index++) {
    const pair = words.slice(index, index + 2).join(" ");
    if (commandAliases[pair] && index + 1 < words.length) {
      result.push(commandAliases[pair]);
      index++;
    } else result.push(commandAliases[words[index]] ?? words[index]);
  }
  return result;
}

/** Keep the actual heard phrase and complete it using the original command catalog.
 * Whole-word matching avoids flicker for partial words; the parser checks every offered completion.
 * A complete hypothesis is still just a suggestion until the speech pipeline recognizes the utterance.
 */
export function commandSuggestions(
  input: string,
  context: CommandSuggestionContext,
): CommandSuggestion[] {
  const heard = input
    .toLowerCase()
    .trim()
    .replace(/^[“”"‘’]+|[\p{P}]+$/gu, "")
    .trim()
    .replace(/\s+/g, " ");
  if (!heard) return [];
  const prefix = tokens(heard);
  if (!prefix.length) return [];
  const result: CommandSuggestion[] = [];
  for (const command of commandCatalog) {
    if (!available(command.id, context)) continue;
    const words = command.label.split(" ");
    // Try each word boundary so multiword aliases and polite articles retain the spoken spelling.
    for (let count = 1; count <= words.length; count++) {
      const candidate = tokens(words.slice(0, count).join(" "));
      if (
        candidate.length !== prefix.length ||
        !candidate.every((token, index) => token === prefix[index])
      )
        continue;
      const remaining = words.slice(count).join(" ");
      if (parseCommand(`${heard} ${remaining}`, context) !== command.id)
        continue;
      result.push({ id: command.id, heard, remaining });
      break;
    }
  }
  return result;
}

/** Keep the everyday guide stable, even when a selection or playback changes the live suggestions. */
export const commonCommands: CommonCommand[] = [
  { id: Command.START_ENTRY, description: "Record a new entry" },
  { id: Command.RESUME_ENTRY, description: "Add to this entry" },
  { id: Command.PLAY_ENTRY, description: "Hear your recording" },
  { id: Command.STOP_ENTRY, description: "Finish recording this entry" },
].map((command) => ({
  ...command,
  label: commandCatalog.find((item) => item.id === command.id)!.label,
}));

/** Offer actions for an explicit selection, independently of microphone state.
 * Browsing supplies its own moving selection; replacement and dialogs own their
 * actions. Never offer copying or playing words without their source recording.
 */
export function selectionSuggestions(
  context: CommandSuggestionContext,
): CommonCommand[] {
  const { entry, dialog, replacement, browse } = context;
  if (
    dialog ||
    replacement ||
    browse ||
    entry.selection.end <= entry.selection.start
  )
    return [];
  const recorded = hasCompleteAudio(copyPassage(entry, entry.selection));
  const actions = [
    {
      id: Command.PLAY_SELECTION,
      description: "Play the selected words using your original recording.",
    },
    {
      id: Command.UPDATE_SELECTION,
      description:
        "Speak a replacement for the selected words, then accept or cancel it.",
    },
    {
      id: Command.COPY_SELECTION,
      description:
        "Copy the selected words and their audio to the Lingual clipboard.",
    },
    {
      id: Command.DELETE_SELECTION,
      description:
        "Delete the selected words and their linked audio from this entry. Undo restores them.",
    },
    {
      id: Command.REMOVE_SELECTION,
      description: "Clear the selection without changing any words or audio.",
    },
  ];
  return actions
    .filter(
      (action) =>
        recorded ||
        ![Command.PLAY_SELECTION, Command.COPY_SELECTION].includes(action.id),
    )
    .map((action) => ({
      ...action,
      label: commandCatalog.find((command) => command.id === action.id)!.label,
    }));
}

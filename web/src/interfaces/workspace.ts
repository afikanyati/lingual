import type { Entry, TextSelection } from "./entry";
import type { Passage } from "./timeline";
import type { Command } from "../enums/command";
export interface Preferences {
  punctuation: boolean;
  omitSilences: boolean;
  temporalSuggestions: boolean;
  punctuationSuggestions: boolean;
  formattingSuggestions: boolean;
  passiveEcho: boolean;
  capitalization: boolean;
  voiceFeedback: boolean;
  voiceURI: string;
  volume: number;
  echoRate: number;
  playbackRate: number;
}
export interface SelectionUpdate {
  range: TextSelection;
  passage: Passage;
}
export interface BrowseState {
  mode: "walk" | "run";
  scope: "entry" | "selection" | "commit" | "list";
  ranges: TextSelection[];
  index: number;
  paused: boolean;
}
export interface CommandContext {
  playback?: "audio" | "echo";
  dialog?: "help" | "settings" | "delete" | "export" | null;
  entry: Entry;
  preferences: Preferences;
  clipboard: Passage;
  replacement?: SelectionUpdate;
  browse?: BrowseState;
}
export interface CommandEffect {
  startRecording?: boolean;
  kind:
    | "listen"
    | "stop-listening"
    | "new-entry"
    | "delete-entry"
    | "library"
    | "open-entry"
    | "help"
    | "close-dialog"
    | "confirm-dialog"
    | "permissions"
    | "export"
    | "play"
    | "echo"
    | "pause-playback"
    | "resume-playback"
    | "stop-playback"
    | "pause-echo"
    | "resume-echo"
    | "stop-echo"
    | "seek"
    | "browse";
  range?: TextSelection;
  format?: "audio" | "text" | "choose";
  offset?: number;
  passage?: Passage;
}
export interface CommandOutcome extends CommandContext {
  command: Command;
  effect?: CommandEffect;
  message: string;
}

export interface CommandDescription {
  id: Command;
  label: string;
}
export interface RecordingPosition {
  id: string;
  offset: number;
}

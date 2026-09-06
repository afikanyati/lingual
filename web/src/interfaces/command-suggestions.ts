import type { Command } from "../enums/command";
import type { CommandContext } from "./workspace";

export interface CommandSuggestionContext extends CommandContext {
  listening?: boolean;
}

export interface CommandSuggestion {
  id: Command;
  heard: string;
  remaining: string;
}

export interface CommonCommand {
  id: Command;
  label: string;
  description: string;
}

export interface CommandCompletionsProps {
  suggestions: CommandSuggestion[];
}

export interface CommandGuideProps {
  commands: CommonCommand[];
  onExplore: () => void;
}

export interface SelectionSuggestionsProps {
  commands: CommonCommand[];
  onAction: (command: Command) => void;
}

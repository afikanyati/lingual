import type {
  CommandCompletionsProps,
  CommandGuideProps,
  SelectionSuggestionsProps,
} from "../../interfaces/command-suggestions";
import { Button } from "../Button";

/** Suggestions are read-only: only the speech pipeline can accept an utterance. */
export function CommandCompletions({ suggestions }: CommandCompletionsProps) {
  if (!suggestions.length) return null;
  return (
    <section
      className="command-completions"
      aria-label="Possible voice commands"
      aria-live="polite"
      aria-atomic="true"
    >
      <span className="command-discovery-label">Possible commands</span>
      <ul>
        {suggestions.map((suggestion) => (
          <li key={suggestion.id}>
            <mark>{suggestion.heard}</mark>
            {suggestion.remaining && (
              <>
                {" "}
                <span className="command-remaining">
                  {suggestion.remaining}
                </span>
              </>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

/** Keep selection actions in the same discovery area, without implying speech was heard. */
export function SelectionSuggestions({
  commands,
  onAction,
}: SelectionSuggestionsProps) {
  if (!commands.length) return null;
  return (
    <section
      className="command-completions selection-suggestions"
      aria-label="Suggested selection actions"
    >
      <span className="command-discovery-label">For this selection</span>
      <ul>
        {commands.map((command) => (
          <li key={command.id}>
            <Button
              tooltip={command.description}
              onClick={() => onAction(command.id)}
            >
              {command.label}
            </Button>
          </li>
        ))}
      </ul>
    </section>
  );
}

export function CommandGuide({ commands, onExplore }: CommandGuideProps) {
  return (
    <section className="command-guide" aria-label="Voice command guide">
      <div className="command-guide-heading">
        <h2>While listening, say…</h2>
        <Button
          tooltip="Explore every voice action and its meaning."
          className="text-link"
          onClick={onExplore}
        >
          All voice actions
        </Button>
      </div>
      <ul>
        {commands.map((command) => (
          <li key={command.id}>
            <span className="command-phrase">“{command.label}”</span>
            <span className="command-purpose">{command.description}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}

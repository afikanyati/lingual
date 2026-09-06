import type { BooleanSettingDescription } from "../interfaces/settings";

/** User-facing explanations follow the native behavior; headphone use is confirmed per session. */
export const booleanSettings: BooleanSettingDescription[] = [
  {
    key: "punctuation",
    label: "Punctuation",
    description:
      "Say punctuation names, such as comma and period, during synthesized read-back.",
  },
  {
    key: "omitSilences",
    label: "Omit Silences",
    description:
      "Skip the pauses between recorded words during edited-entry playback. Original recordings stay intact.",
  },
  {
    key: "temporalSuggestions",
    label: "Temporal Suggestions",
    description: "Represent pauses with spacing in the audio-linked view.",
  },
  {
    key: "punctuationSuggestions",
    label: "Punctuation suggestions",
    description:
      "Show punctuation from speech and pauses. Turn off to hide it; original text and audio are preserved.",
  },
  {
    key: "formattingSuggestions",
    label: "Formatting Suggestions",
    description: "Emphasize words using changes in your voice's intensity.",
  },
  {
    key: "passiveEcho",
    label: "Passive Echo",
    description:
      "Read each captured passage back while you continue dictating. Requires headphones.",
  },
  {
    key: "capitalization",
    label: "Capitalization",
    description:
      "Keep recognized capital letters and capitalize suggested sentence starts. Turn off to display lowercase text.",
  },
  {
    key: "voiceFeedback",
    label: "Voice Feedback",
    description:
      "Play sounds and spoken confirmations for actions and speech processing. Spoken feedback requires headphones.",
  },
];

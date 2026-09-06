import type { HeadphoneReminderContext } from "../interfaces/headphones";
import { HeadphoneStatus } from "../enums/headphones";

/** Explain only the audio features currently being requested.
 * Output detection is live device state; it is not a stored preference.
 * Keep ordinary dictation and speaker playback available without headphones.
 */
export function headphoneReminder(context: HeadphoneReminderContext): string {
  const { preferences } = context;
  if (context.headphoneStatus === HeadphoneStatus.Headphones) return "";
  const reasons: string[] = [];
  if (context.browsing) reasons.push("hear audio while walking or running");
  else if (context.selection) reasons.push("repeat the selected audio");
  if (context.handsFreePlayback)
    reasons.push("use voice actions during playback");
  const listeningFeatures = context.listening || context.settingsOpen;
  if (
    preferences.passiveEcho &&
    (listeningFeatures || context.requestedFeature === "passiveEcho")
  )
    reasons.push("hear passive echo");
  if (
    preferences.voiceFeedback &&
    (listeningFeatures || context.requestedFeature === "voiceFeedback")
  )
    reasons.push("hear spoken feedback");
  if (!reasons.length) return "";
  const purpose =
    reasons.length === 1
      ? reasons[0]
      : `${reasons.slice(0, -1).join(", ")} and ${reasons.at(-1)}`;
  if (context.headphoneStatus === HeadphoneStatus.Unknown)
    return "Lingual can’t identify your audio output. Automatic headphone audio is paused.";
  return `Connect headphones and select them as your system audio output to ${purpose}.`;
}

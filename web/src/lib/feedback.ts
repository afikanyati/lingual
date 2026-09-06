/** Reuse Lingual's original earcons; playback failure must never break editing. */
export function playFeedback(
  name:
    | "voice-command-accept"
    | "voice-command-deny"
    | "start-listening"
    | "stop-listening"
    | "commit-buffer"
    | "paragraph-suggestion"
    | "sentence-suggestion"
    | "speech-registered"
    | "play"
    | "delete"
    | "dialog"
    | "repeat"
    | "processing"
    | "save"
    | "startup"
    | "error",
  volume: number,
): void {
  const audio = new Audio(`${import.meta.env.BASE_URL}sounds/${name}.wav`);
  audio.volume = Math.min(1, Math.max(0, volume));
  void audio.play().catch(() => {});
  navigator.vibrate?.(20);
}

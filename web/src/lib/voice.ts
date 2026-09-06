import { MAX_VOICE_PITCH, MIN_VOICE_PITCH, pitchNote } from "./pitch";

/** A stable acoustic baseline replaces native Speaker.pitch; it does not label the speaker's identity. */
export class SpeakerPitch {
  private samples: number[] = [];
  value?: number;
  constructor(saved?: number) {
    if (saved && saved >= MIN_VOICE_PITCH && saved <= MAX_VOICE_PITCH)
      this.value = saved;
  }
  add(frequency?: number): number | undefined {
    if (this.value !== undefined) return this.value;
    if (
      !frequency ||
      frequency < MIN_VOICE_PITCH ||
      frequency > MAX_VOICE_PITCH
    )
      return;
    this.samples.push(frequency);
    if (this.samples.length < 15) return;
    this.value =
      this.samples.reduce((sum, sample) => sum + sample, 0) /
      this.samples.length;
    this.samples = [];
    return this.value;
  }
  reset(): void {
    this.samples = [];
  }
}

/** Mirror Utils.getSynthesizerVoice's named local voices, while honoring an explicit user choice first.
 * Browsers do not expose acoustic register metadata for arbitrary voices; fall back to the local locale voice.
 */
export function chooseLocalVoice(
  available: SpeechSynthesisVoice[],
  selected: string,
  frequency: number | undefined,
  locale: string,
): SpeechSynthesisVoice | undefined {
  const voices = available.filter(
    (voice) => voice.localService && /^en(?:-|$)/i.test(voice.lang),
  );
  const explicit = voices.find((voice) => voice.voiceURI === selected);
  if (explicit) return explicit;
  const high = Number(pitchNote(frequency).slice(-1)) >= 4;
  const region = locale.toUpperCase().split("-").at(-1);
  const name =
    region === "AU"
      ? high
        ? "Karen"
        : "Lee"
      : region === "GB" || region === "UK"
        ? high
          ? "Kate"
          : "Oliver"
        : high
          ? "Ava"
          : "Tom";
  return (
    voices.find((voice) => voice.name === `${name} (Enhanced)`) ??
    voices.find((voice) => voice.name === name) ??
    voices.find((voice) => voice.lang.toLowerCase() === locale.toLowerCase()) ??
    voices.find((voice) => voice.default) ??
    voices[0]
  );
}

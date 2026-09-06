import type { PitchReading } from "../interfaces/pitch";

// ** IMPORTANT **: Keep in sync with diction-processor/Utils.swift's voiced speech limits.
export const MIN_VOICE_PITCH = 82;
export const MAX_VOICE_PITCH = 1047;
const FRAME_SIZE = 1024;
const SAMPLE_RATE = 16000;

export function powerDb(audio: Float32Array): number {
  if (!audio.length) return -160;
  const energy =
    audio.reduce((sum, value) => sum + value ** 2, 0) / audio.length;
  return energy ? Math.max(-160, 10 * Math.log10(energy)) : -160;
}

/** Port of Beethoven's YIN difference, cumulative normalization, threshold and parabolic interpolation.
 * Native YIN accepts its global minimum even for noise; reject those unvoiced minima instead.
 */
export function estimatePitch(
  audio: Float32Array,
  sampleRate = SAMPLE_RATE,
): number | undefined {
  if (audio.length < 512 || powerDb(audio) < -65) return;
  const half = Math.floor(Math.min(audio.length, 2048) / 2);
  const difference = new Float64Array(half);
  let sum = 0;
  difference[0] = 1;
  for (let lag = 1; lag < half; lag++) {
    let distance = 0;
    for (let index = 0; index < half; index++)
      distance += (audio[index] - audio[index + lag]) ** 2;
    sum += distance;
    difference[lag] = sum ? (distance * lag) / sum : 1;
  }
  // Search all periods first: restricting lags to the speech range can alias an out-of-range tone.
  for (let lag = 2; lag < half - 1; lag++) {
    if (difference[lag] >= 0.05) continue;
    while (lag + 1 < half && difference[lag + 1] < difference[lag]) lag++;
    const left = difference[lag - 1];
    const middle = difference[lag];
    const right = difference[Math.min(half - 1, lag + 1)];
    const denominator = 2 * (2 * middle - right - left);
    const adjustment = denominator ? (right - left) / denominator : 0;
    const period = lag + (Math.abs(adjustment) <= 1 ? adjustment : 0);
    const frequency = sampleRate / period;
    if (
      frequency < MIN_VOICE_PITCH / 2 ** (5 / 1200) ||
      frequency > MAX_VOICE_PITCH * 2 ** (5 / 1200)
    )
      return;
    return Math.min(MAX_VOICE_PITCH, Math.max(MIN_VOICE_PITCH, frequency));
  }
}

/** Native Pitchy uses equal temperament with A4 = 440 Hz, not the older experimental Utils lookup table. */
export function pitchNote(frequency: number | undefined): string {
  if (
    !frequency ||
    !Number.isFinite(frequency) ||
    frequency < 20 ||
    frequency > 4190
  )
    return "";
  const lower = Math.floor(69 + 12 * Math.log2(frequency / 440));
  const lowerHz = 440 * 2 ** ((lower - 69) / 12);
  const higherHz = 440 * 2 ** ((lower + 1 - 69) / 12);
  const midi = frequency - lowerHz < higherHz - frequency ? lower : lower + 1;
  const letters = [
    "C",
    "C#",
    "D",
    "D#",
    "E",
    "F",
    "F#",
    "G",
    "G#",
    "A",
    "A#",
    "B",
  ];
  return `${letters[((midi % 12) + 12) % 12]}${Math.floor(midi / 12) - 1}`;
}

/** Take the median of voiced frames so consonant onsets/silence cannot mask the pitch of a whole word. */
export function wordPitch(audio: Float32Array): number | undefined {
  const frequencies: number[] = [];
  for (let offset = 0; offset + 512 <= audio.length; offset += FRAME_SIZE / 2) {
    const frequency = estimatePitch(
      audio.subarray(offset, Math.min(audio.length, offset + FRAME_SIZE)),
    );
    if (frequency !== undefined) frequencies.push(frequency);
  }
  if (!frequencies.length) return;
  frequencies.sort((a, b) => a - b);
  return frequencies[Math.floor(frequencies.length / 2)];
}

/** Bounded live analysis over the existing microphone stream; never opens a competing audio session. */
export class PitchTracker {
  private frame = new Float32Array(FRAME_SIZE);
  private used = 0;
  private samples = 0;
  process(audio: Float32Array): PitchReading | undefined {
    let latest: PitchReading | undefined;
    for (const sample of audio) {
      this.frame[this.used++] = sample;
      this.samples++;
      if (this.used < FRAME_SIZE) continue;
      const frequency = estimatePitch(this.frame);
      latest = {
        frequency,
        note: pitchNote(frequency),
        power: powerDb(this.frame),
        time: this.samples / SAMPLE_RATE,
      };
      this.used = 0;
    }
    return latest;
  }
  reset(): void {
    this.used = 0;
    this.samples = 0;
    this.frame.fill(0);
  }
}

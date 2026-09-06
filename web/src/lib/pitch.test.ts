import { expect, it } from "vitest";
import { estimatePitch, pitchNote, PitchTracker, wordPitch } from "./pitch";
const tone = (hz: number, length = 2048, amplitude = 0.15) => Float32Array.from({ length }, (_, i) => amplitude * Math.sin(2 * Math.PI * hz * i / 16000));

it.each([82, 110, 196, 220, 261.626, 440, 880, 1047])("uses native YIN pitch estimation throughout the speech range: %s Hz", (frequency) => {
  expect(Math.abs(1200 * Math.log2(estimatePitch(tone(frequency))! / frequency))).toBeLessThan(5);
});
it("maps frequency to the native Pitchy note convention, including sharps and octaves", () => {
  expect(pitchNote(440)).toBe("A4");
  expect(pitchNote(261.626)).toBe("C4");
  expect(pitchNote(277.183)).toBe("C#4");
  expect(pitchNote(82.407)).toBe("E2");
  expect(pitchNote(undefined)).toBe("");
  expect(pitchNote(Number.NaN)).toBe("");
});
it("rejects silence, DC, non-periodic noise and frequencies outside native voiced limits", () => {
  expect(estimatePitch(new Float32Array(2048))).toBeUndefined();
  expect(estimatePitch(new Float32Array(2048).fill(0.2))).toBeUndefined();
  let seed = 19;
  const noise = Float32Array.from({ length: 2048 }, () => { seed = (seed * 1664525 + 1013904223) >>> 0; return ((seed / 2 ** 32) - 0.5) * 0.3; });
  expect(estimatePitch(noise)).toBeUndefined();
  expect(estimatePitch(tone(55))).toBeUndefined();
  expect(estimatePitch(tone(1300))).toBeUndefined();
});
it("keeps the fundamental when a higher harmonic is louder", () => {
  const audio = tone(160);
  const harmonic = tone(320, audio.length, 0.23);
  audio.forEach((_, i) => audio[i] += harmonic[i]);
  expect(estimatePitch(audio)).toBeCloseTo(160, 0);
});
it("uses voiced frames across the word instead of measuring only its unvoiced onset", () => {
  const audio = new Float32Array(6000);
  audio.set(tone(220, 3000), 2500);
  expect(wordPitch(audio)).toBeCloseTo(220, 0);
});
it("tracks live pitch through packet boundaries, clears in silence, and resets on a new capture", () => {
  const tracker = new PitchTracker();
  expect(tracker.process(tone(220, 100))).toBeUndefined();
  expect(tracker.process(tone(220, 4096))?.frequency).toBeCloseTo(220, 0);
  expect(tracker.process(new Float32Array(4096))?.frequency).toBeUndefined();
  tracker.reset();
  expect(tracker.process(tone(440, 4096))?.note).toBe("A4");
});
it("uses Pitch.offsets.closest's frequency midpoint rather than the logarithmic midpoint between notes", () => {
  const a = 440;
  const sharp = 440 * 2 ** (1 / 12);
  expect(pitchNote(Math.sqrt(a * sharp) + 0.01)).toBe("A4");
  expect(pitchNote((a + sharp) / 2 + 0.01)).toBe("A#4");
});

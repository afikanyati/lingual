import { describe, it, expect } from "vitest";
import { encodeWav, joinSamples, hasSpeechEnergy } from "./audio";
describe("audio integrity", () => {
  it("preserves final partial chunks and sequence", () => {
    expect([
      ...joinSamples([new Float32Array([1, 2]), new Float32Array([3])]),
    ]).toEqual([1, 2, 3]);
  });
  it("encodes a valid mono PCM WAV with the original duration", async () => {
    const wav = encodeWav(new Float32Array([0, 1, -1]), 16000);
    const data = new DataView(await wav.arrayBuffer());
    expect(data.getUint32(24, true)).toBe(16000);
    expect(data.getUint32(40, true)).toBe(6);
    expect(data.getInt16(46, true)).toBe(32767);
    expect(data.getInt16(48, true)).toBe(-32768);
  });
  it("skips pure silence but keeps quiet speech", () => {
    expect(hasSpeechEnergy(new Float32Array(16000))).toBe(false);
    expect(hasSpeechEnergy(new Float32Array(16000).fill(0.005))).toBe(true);
  });
});

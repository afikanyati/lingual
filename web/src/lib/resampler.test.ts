import { describe, it, expect } from "vitest";
import { SpeechResampler } from "./resampler";
import { joinSamples } from "./audio";
describe("microphone resampling", () => {
  for (const rate of [16000, 44100, 48000])
    it(`preserves duration across arbitrary ${rate} Hz chunks`, () => {
      const input = Float32Array.from({ length: rate }, (_, i) =>
        Math.sin((2 * Math.PI * 220 * i) / rate),
      );
      const sampler = new SpeechResampler(rate);
      const chunks: Float32Array[] = [];
      for (let index = 0; index < input.length; index += 2048)
        chunks.push(sampler.process(input.subarray(index, index + 2048)));
      const output = joinSamples(chunks);
      expect(output.length).toBe(16000);
      expect(output[400]).toBeCloseTo(-0.02, 1);
    });
});

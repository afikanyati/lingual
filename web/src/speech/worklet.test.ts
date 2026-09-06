import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { describe, it, expect } from "vitest";
import { SpeechResampler } from "../lib/resampler";

/** Execute the shipped processor, including its message port and final partial packet. */
describe("production audio worklet", () => {
  for (const sampleRate of [16000, 44100, 48000]) {
    it(`matches compatibility resampling at ${sampleRate} Hz and flushes only once`, () => {
      const messages: { audio?: Float32Array; stopped?: boolean }[] = [];
      let Processor: any;
      runInNewContext(readFileSync("public/capture-worklet.js", "utf8"), {
        sampleRate,
        AudioWorkletProcessor: class {
          port = {
            postMessage: (data: { audio?: Float32Array }) =>
              messages.push(data),
            onmessage: (_: unknown) => {},
          };
        },
        registerProcessor: (_: string, constructor: any) => {
          Processor = constructor;
        },
      });
      const processor = new Processor();
      const input = Float32Array.from(
        { length: sampleRate },
        (_, i) => Math.sin((2 * Math.PI * 220 * i) / sampleRate) * 0.1,
      );
      for (let offset = 0; offset < input.length; offset += 128)
        processor.process([[input.subarray(offset, offset + 128)]]);
      processor.port.onmessage({ data: "flush" });
      const audio = Float32Array.from(
        messages.flatMap((message) =>
          message.audio ? [...message.audio] : [],
        ),
      );
      expect(audio).toEqual(new SpeechResampler(sampleRate).process(input));
      expect(audio).toHaveLength(16000);
      expect(messages.at(-1)).toEqual({ stopped: true });
      const count = messages.length;
      processor.process([[input]]);
      expect(messages).toHaveLength(count);
    });
  }
});

/** Streaming sample-rate conversion keeps fractional positions across chunks (including 44.1 kHz). */
// ** IMPORTANT **: Keep in sync with public/capture-worklet.js.
export class SpeechResampler {
  private weight = 0;
  private sum = 0;
  private ratio: number;
  constructor(sampleRate: number) {
    if (!Number.isFinite(sampleRate) || sampleRate <= 0)
      throw new Error("Invalid microphone sample rate.");
    this.ratio = sampleRate / 16000;
  }
  process(input: Float32Array): Float32Array {
    const output: number[] = [];
    for (const sample of input) {
      let remaining = 1;
      while (remaining > 1e-8) {
        const amount = Math.min(remaining, this.ratio - this.weight);
        this.sum += sample * amount;
        this.weight += amount;
        remaining -= amount;
        if (this.weight >= this.ratio - 1e-8) {
          output.push(this.sum / this.ratio);
          this.sum = 0;
          this.weight = 0;
        }
      }
    }
    return Float32Array.from(output);
  }
}

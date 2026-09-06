/* Accumulate microphone samples off the UI thread; flush the last partial packet on stop. */
class LingualCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.samples = new Float32Array(2048);
    this.offset = 0;
    this.ratio = sampleRate / 16000;
    this.weight = 0;
    this.sum = 0;
    this.port.onmessage = ({ data }) => {
      if (data === "flush") {
        this.finished = true;
        this.flush();
        this.port.postMessage({ stopped: true });
      }
    };
  }
  flush() {
    if (!this.offset) return;
    const audio = this.samples.slice(0, this.offset);
    this.port.postMessage({ audio }, [audio.buffer]);
    this.offset = 0;
  }
  process(inputs) {
    if (this.finished) return true;
    const channel = inputs[0]?.[0];
    if (!channel) return true;
    // Keep the AudioContext at the device rate; resample only the speech input.
    // ** IMPORTANT **: Keep in sync with src/lib/resampler.ts.
    // A persistent weighted resampler preserves time across render blocks, including 44.1 kHz input.
    for (const sample of channel) {
      let remaining = 1;
      while (remaining > 1e-8) {
        const amount = Math.min(remaining, this.ratio - this.weight);
        this.sum += sample * amount;
        this.weight += amount;
        remaining -= amount;
        if (this.weight >= this.ratio - 1e-8) {
          this.samples[this.offset++] = this.sum / this.ratio;
          this.sum = 0;
          this.weight = 0;
          if (this.offset === this.samples.length) this.flush();
        }
      }
    }
    return true;
  }
}
registerProcessor("lingual-capture", LingualCapture);

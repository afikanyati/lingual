import { PitchTracker } from "../lib/pitch";
import { SpeechResampler } from "../lib/resampler";
import type { CaptureCallbacks } from "../interfaces/speech";
import { hasSpeechEnergy, joinSamples } from "../lib/audio";

/** Microphone ownership is generation-scoped, including delayed permission responses. */
export class MicrophoneCapture {
  private generation = 0;
  private pitch = new PitchTracker();
  private stream?: MediaStream;
  private context?: AudioContext;
  private source?: MediaStreamAudioSourceNode;
  private fallback?: ScriptProcessorNode;
  private node?: AudioWorkletNode;
  private chunks: Float32Array[] = [];
  private sampleCount = 0;
  private silence = 0;
  private voiced = false;
  private stopped?: () => void;
  private stopping?: Promise<void>;
  private finalCompatibilityBuffer?: () => void;
  constructor(private callbacks: CaptureCallbacks) {}

  async start(): Promise<void> {
    const generation = ++this.generation;
    this.pitch.reset();
    try {
      if (!navigator.mediaDevices?.getUserMedia)
        throw new Error(
          "Microphone recording requires localhost or HTTPS in a supported browser.",
        );
      console.debug("[Lingual capture] Requesting microphone permission");
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });
      // A cancelled permission dialog must never activate a microphone later.
      if (generation !== this.generation) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      this.stream = stream;
      stream.getAudioTracks().forEach((track) =>
        track.addEventListener("ended", () => {
          if (generation !== this.generation) return;
          this.callbacks.onInterrupted(
            "The microphone disconnected. Your recording is being saved. Reconnect it, then start listening again.",
          );
        }),
      );
      console.debug(
        "[Lingual capture] Microphone granted; preparing audio context",
      );
      const context = new AudioContext();
      this.context = context;
      await context.resume();
      console.debug("[Lingual capture] Audio context running; loading worklet");
      this.source = context.createMediaStreamSource(stream);
      const mute = context.createGain();
      mute.gain.value = 0;
      mute.connect(context.destination);
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        await Promise.race([
          context.audioWorklet.addModule(
            `${import.meta.env.BASE_URL}capture-worklet.js`,
          ),
          new Promise<never>((_, reject) => {
            timeout = setTimeout(
              () => reject(new Error("Audio worklet startup timed out.")),
              3000,
            );
          }),
        ]);
        if (generation !== this.generation) {
          await this.release();
          return;
        }
        const node = new AudioWorkletNode(context, "lingual-capture");
        this.node = node;
        node.port.onmessage = ({
          data,
        }: MessageEvent<{ audio?: Float32Array; stopped?: boolean }>) => {
          if (data.audio) this.receive(data.audio);
          if (data.stopped) this.stopped?.();
        };
        this.source.connect(node);
        node.connect(mute);
        console.debug("[Lingual capture] Worklet ready");
      } catch (error) {
        if (generation !== this.generation) {
          await this.release();
          return;
        }
        // Worklet loading can fail or stall. Keep capture available through the compatibility path.
        console.debug("[Lingual capture] Using compatibility capture:", error);
        const fallback = context.createScriptProcessor(4096, 1, 1);
        this.fallback = fallback;
        const resampler = new SpeechResampler(context.sampleRate);
        fallback.onaudioprocess = (event) => {
          this.receive(resampler.process(event.inputBuffer.getChannelData(0)));
          this.finalCompatibilityBuffer?.();
        };
        this.source.connect(fallback);
        fallback.connect(mute);
      } finally {
        clearTimeout(timeout);
      }
      context.onstatechange = () => {
        if (context.state === "suspended" && generation === this.generation)
          this.callbacks.onInterrupted(
            "The browser paused microphone access. Your captured speech is saved; press Listen to resume.",
          );
      };
    } catch (error) {
      await this.release();
      if (generation !== this.generation) return;
      throw error;
    }
  }
  private receive(audio: Float32Array): void {
    this.callbacks.onAudio?.(audio);
    const reading = this.pitch.process(audio);
    if (reading) this.callbacks.onPitch?.(reading);
    this.chunks.push(audio);
    this.sampleCount += audio.length;
    const energy = Math.sqrt(
      audio.reduce((sum, value) => sum + value * value, 0) / audio.length,
    );
    this.callbacks.onLevel?.(Math.min(1, energy * 12));
    if (hasSpeechEnergy(audio)) {
      this.voiced = true;
      this.silence = 0;
    } else this.silence += audio.length;
    // End on a natural pause, with a bounded chunk for continuous or silent input.
    if (
      (this.voiced && this.silence >= 12800 && this.sampleCount >= 16000) ||
      this.sampleCount >= 240000
    )
      this.flush();
  }
  private flush(): void {
    if (!this.sampleCount) return;
    this.callbacks.onChunk(joinSamples(this.chunks));
    this.chunks = [];
    this.sampleCount = 0;
    this.silence = 0;
    this.voiced = false;
  }
  async stop(): Promise<void> {
    if (this.stopping) return this.stopping;
    ++this.generation;
    this.stopping = (async () => {
      if (this.node && this.context?.state === "running") {
        await new Promise<void>((resolve) => {
          const timer = setTimeout(resolve, 500);
          this.stopped = () => {
            clearTimeout(timer);
            resolve();
          };
          this.node!.port.postMessage("flush");
        });
      }
      if (this.fallback && this.context?.state === "running") {
        // Drain the callback already scheduled at Stop, instead of truncating its last word.
        await new Promise<void>((resolve) => {
          const timer = setTimeout(resolve, 250);
          this.finalCompatibilityBuffer = () => {
            clearTimeout(timer);
            resolve();
          };
        });
        this.finalCompatibilityBuffer = undefined;
      }
      this.flush();
      await this.release();
      this.callbacks.onLevel?.(0);
      this.pitch.reset();
      this.callbacks.onPitch?.(undefined);
    })();
    try {
      await this.stopping;
    } finally {
      this.stopping = undefined;
    }
  }
  private async release(): Promise<void> {
    this.source?.disconnect();
    this.node?.disconnect();
    if (this.node) {
      this.node.port.onmessage = null;
      this.node.port.close();
    }
    this.stopped = undefined;
    if (this.fallback) {
      this.fallback.onaudioprocess = null;
      this.fallback.disconnect();
      this.fallback = undefined;
    }
    this.stream?.getTracks().forEach((track) => track.stop());
    if (this.context && this.context.state !== "closed")
      await this.context.close();
    this.stream = undefined;
    this.context = undefined;
    this.source = undefined;
    this.node = undefined;
  }
}

import { speechIntervals } from "./speech-pauses";
import type { AudioClip } from "../interfaces/entry";
import type { PlaybackSlice } from "../interfaces/timeline";
import { encodeWav, joinSamples } from "./audio";

export interface PlaybackCallbacks {
  onPosition: (start: number, end: number, seconds: number) => void;
  onEnd: () => void;
}
interface PreparedSlice {
  slice: PlaybackSlice;
  buffer: AudioBuffer;
  begins: number;
  duration: number;
}
/** Schedule the edited timeline from immutable recordings, preserving cut/copy order and per-word speed. */
export class TimelinePlayer {
  private context?: AudioContext;
  private sources: AudioBufferSourceNode[] = [];
  private prepared: PreparedSlice[] = [];
  private startedAt = 0;
  private offset = 0;
  private duration = 0;
  private ticker?: ReturnType<typeof setInterval>;
  private generation = 0;
  private running = false;
  private gain?: GainNode;
  constructor(private callbacks: PlaybackCallbacks) {}

  async load(
    slices: PlaybackSlice[],
    loadClip: (id: string) => Promise<AudioClip | undefined>,
    volume = 1,
  ): Promise<void> {
    this.stop();
    const generation = this.generation;
    const context = this.context ?? new AudioContext();
    this.context = context;
    await context.resume();
    const cache = new Map<string, AudioBuffer>();
    const prepared: PreparedSlice[] = [];
    let total = 0;
    for (const slice of slices) {
      if (!cache.has(slice.clipId)) {
        const clip = await loadClip(slice.clipId);
        if (!clip)
          throw new Error(
            "A source recording is missing. Restore its backup before playing this passage.",
          );
        cache.set(
          slice.clipId,
          await context.decodeAudioData(await clip.audio.arrayBuffer()),
        );
      }
      const buffer = cache.get(slice.clipId)!;
      const start = Math.min(buffer.duration, Math.max(0, slice.start));
      const end = Math.min(buffer.duration, Math.max(start, slice.end));
      const intervals = slice.omitSilences
        ? speechIntervals(
            buffer.getChannelData(0),
            start,
            end,
            buffer.sampleRate,
          )
        : [{ start, end }];
      for (const { start, end } of intervals) {
        const duration = (end - start) / slice.rate;
        if (duration > 0) {
          prepared.push({
            slice: { ...slice, start, end },
            buffer,
            begins: total,
            duration,
          });
          total += duration;
        }
      }
    }
    if (generation !== this.generation) return;
    this.prepared = prepared;
    this.duration = total;
    this.gain = context.createGain();
    this.gain.gain.value = volume;
    this.gain.connect(context.destination);
    this.resume();
  }
  get position(): number {
    return this.running && this.context
      ? Math.min(
          this.duration,
          this.offset + this.context.currentTime - this.startedAt,
        )
      : this.offset;
  }
  setVolume(volume: number): void {
    if (this.gain) this.gain.gain.value = volume;
  }
  changeRate(multiplier: number): void {
    if (!Number.isFinite(multiplier) || multiplier <= 0) return;
    const wasRunning = this.running;
    const position = this.position;
    this.pause();
    let begins = 0;
    this.prepared = this.prepared.map((item) => {
      const updated = {
        ...item,
        begins,
        duration: item.duration / multiplier,
        slice: { ...item.slice, rate: item.slice.rate * multiplier },
      };
      begins += updated.duration;
      return updated;
    });
    this.duration = begins;
    this.offset = position / multiplier;
    if (wasRunning) this.resume();
  }
  pause(): void {
    this.offset = this.position;
    this.stopSources();
  }
  resume(): void {
    const context = this.context;
    if (!context || this.running || !this.gain) return;
    void context.resume();
    this.startedAt = context.currentTime;
    this.running = true;
    for (const prepared of this.prepared) {
      const skipped = Math.max(0, this.offset - prepared.begins);
      if (skipped >= prepared.duration) continue;
      const source = context.createBufferSource();
      source.buffer = prepared.buffer;
      source.playbackRate.value = prepared.slice.rate;
      const gain = context.createGain();
      gain.gain.value = prepared.slice.gain;
      source.connect(gain);
      gain.connect(this.gain);
      source.start(
        context.currentTime + Math.max(0, prepared.begins - this.offset),
        prepared.slice.start + skipped * prepared.slice.rate,
        (prepared.duration - skipped) * prepared.slice.rate,
      );
      this.sources.push(source);
    }
    this.ticker = setInterval(() => {
      const position = this.position;
      const current = this.prepared.find(
        (item) =>
          position >= item.begins && position < item.begins + item.duration,
      );
      if (current)
        this.callbacks.onPosition(
          current.slice.textStart,
          current.slice.textEnd,
          position,
        );
      if (position >= this.duration) {
        this.stop();
        this.prepared = [];
        this.duration = 0;
        this.callbacks.onEnd();
      }
    }, 30);
  }
  /** Seek in the edited timeline by the original text offset, preserving a paused player's state. */
  seekToWord(offset: number): boolean {
    const target = this.prepared.find(({ slice }) => slice.textStart <= offset && slice.textEnd > offset);
    if (!target) return false;
    const wasRunning = this.running;
    this.pause();
    this.offset = target.begins;
    this.callbacks.onPosition(target.slice.textStart, target.slice.textEnd, this.offset);
    if (wasRunning) this.resume();
    return true;
  }
  seek(delta: number): void {
    const next = Math.max(0, Math.min(this.duration, this.position + delta));
    this.pause();
    this.offset = next;
    this.resume();
  }
  stop(): void {
    ++this.generation;
    this.stopSources();
    this.offset = 0;
    this.gain?.disconnect();
    this.gain = undefined;
  }
  private stopSources(): void {
    this.running = false;
    clearInterval(this.ticker);
    for (const source of this.sources) {
      try {
        source.stop();
      } catch {
        /* A scheduled source may have already ended. */
      }
      source.disconnect();
    }
    this.sources = [];
  }
  async dispose(): Promise<void> {
    this.stop();
    await this.context?.close();
    this.context = undefined;
  }
}

/** Render precisely the same edited slice order for an exported WAV, including selection speed changes. */
export async function renderTimeline(
  slices: PlaybackSlice[],
  loadClip: (id: string) => Promise<AudioClip | undefined>,
): Promise<Blob> {
  const context = new AudioContext({ sampleRate: 16000 });
  const cache = new Map<string, AudioBuffer>();
  const chunks: Float32Array[] = [];
  try {
    for (const slice of slices) {
      if (!cache.has(slice.clipId)) {
        const clip = await loadClip(slice.clipId);
        if (!clip) throw new Error("A source recording is missing.");
        cache.set(
          slice.clipId,
          await context.decodeAudioData(await clip.audio.arrayBuffer()),
        );
      }
      const source = cache.get(slice.clipId)!;
      const channel = source.getChannelData(0);
      const intervals = slice.omitSilences
        ? speechIntervals(channel, slice.start, slice.end, source.sampleRate)
        : [{ start: slice.start, end: slice.end }];
      for (const interval of intervals) {
        const length = Math.max(
          0,
          Math.floor(
            ((Math.min(source.duration, interval.end) - interval.start) *
              16000) /
              slice.rate,
          ),
        );
        const output = new Float32Array(length);
        for (let index = 0; index < length; index++) {
          const position =
            (interval.start + (index * slice.rate) / 16000) * source.sampleRate;
          const left = Math.floor(position);
          const fraction = position - left;
          output[index] =
            ((channel[left] ?? 0) * (1 - fraction) +
              (channel[left + 1] ?? 0) * fraction) *
            slice.gain;
        }
        chunks.push(output);
      }
    }
    return encodeWav(joinSamples(chunks));
  } finally {
    await context.close();
  }
}

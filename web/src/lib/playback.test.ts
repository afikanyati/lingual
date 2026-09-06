import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TimelinePlayer, renderTimeline } from "./playback";
import type { PlaybackSlice } from "../interfaces/timeline";
import type { AudioClip } from "../interfaces/entry";

const makeSource = () => ({
  buffer: undefined as unknown,
  playbackRate: { value: 1 },
  connect: vi.fn(),
  disconnect: vi.fn(),
  start: vi.fn(),
  stop: vi.fn(),
});
const makeGain = () => ({
  gain: { value: 1 },
  connect: vi.fn(),
  disconnect: vi.fn(),
});
/** A controllable hardware clock tests scheduling independently from wall-clock/OS audio latency. */
class AudioClock {
  static latest: AudioClock;
  currentTime = 0;
  destination = {};
  sources: ReturnType<typeof makeSource>[] = [];
  gains: ReturnType<typeof makeGain>[] = [];
  resume = vi.fn(async () => {});
  close = vi.fn(async () => {});
  decodeAudioData = vi.fn(async () => ({
    duration: 10,
    sampleRate: 16000,
    getChannelData: () => new Float32Array(160000).fill(0.25),
  }));
  constructor() {
    AudioClock.latest = this;
  }
  createBufferSource() {
    const node = makeSource();
    this.sources.push(node);
    return node;
  }
  createGain() {
    const node = makeGain();
    this.gains.push(node);
    return node;
  }
}
const slices: PlaybackSlice[] = [
  { clipId: "a", start: 1, end: 3, rate: 1, gain: 1, textStart: 0, textEnd: 3 },
  {
    clipId: "a",
    start: 5,
    end: 9,
    rate: 2,
    gain: 0.5,
    textStart: 4,
    textEnd: 7,
  },
];
const clip = { audio: new Blob([new Uint8Array([0])]) } as AudioClip;
const loadClip = vi.fn(async () => clip);
let player: TimelinePlayer;
let onEnd: ReturnType<typeof vi.fn>;
let onPosition: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.useFakeTimers();
  vi.stubGlobal("AudioContext", AudioClock);
  loadClip.mockClear();
  onEnd = vi.fn();
  onPosition = vi.fn();
  player = new TimelinePlayer({ onEnd, onPosition });
});
afterEach(async () => {
  await player.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("Lingual note playback specifications", () => {
  it("LTS-030 LTS-031 pause freezes the position and timer; resume uses the remaining source samples", async () => {
    await player.load(slices, loadClip);
    const clock = AudioClock.latest;
    clock.currentTime = 1.25;
    vi.advanceTimersByTime(30);
    expect(onPosition).toHaveBeenLastCalledWith(0, 3, 1.25);
    player.pause();
    const count = onPosition.mock.calls.length;
    clock.currentTime = 50;
    vi.advanceTimersByTime(1000);
    expect(player.position).toBe(1.25);
    expect(onPosition).toHaveBeenCalledTimes(count);
    expect(vi.getTimerCount()).toBe(0);
    player.resume();
    expect(clock.sources[2].start).toHaveBeenCalledWith(50, 2.25, 0.75);
    clock.currentTime = 50.5;
    expect(player.position).toBe(1.75);
  });
  it("LTS-022 completion clears scheduled nodes and timer and emits exactly one end", async () => {
    await player.load(slices, loadClip);
    const clock = AudioClock.latest;
    clock.currentTime = 4;
    vi.advanceTimersByTime(30);
    expect(onEnd).toHaveBeenCalledOnce();
    expect(player.position).toBe(0);
    expect(
      clock.sources.every((s) => s.disconnect.mock.calls.length === 1),
    ).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
    vi.advanceTimersByTime(1000);
    expect(onEnd).toHaveBeenCalledOnce();
    expect(clock.gains[0].disconnect).toHaveBeenCalledOnce();
  });
  it("LTS-028 highlights word boundaries in edited source order without selecting gaps", async () => {
    await player.load(slices, loadClip);
    const clock = AudioClock.latest;
    clock.currentTime = 1.99;
    vi.advanceTimersByTime(30);
    expect(onPosition).toHaveBeenLastCalledWith(0, 3, 1.99);
    clock.currentTime = 2;
    vi.advanceTimersByTime(30);
    expect(onPosition).toHaveBeenLastCalledWith(4, 7, 2);
  });
  it("LTS-057 changes playback speed without jumping to a different source word", async () => {
    await player.load(slices, loadClip);
    const clock = AudioClock.latest;
    clock.currentTime = 1;
    player.changeRate(2);
    expect(player.position).toBe(0.5);
    expect(clock.sources[2].start).toHaveBeenCalledWith(1, 2, 1);
    expect(clock.sources[2].playbackRate.value).toBe(2);
    expect(clock.sources[3].playbackRate.value).toBe(4);
  });
  it("LTS-057 changing rate while paused does not restart playback", async () => {
    await player.load(slices, loadClip);
    AudioClock.latest.currentTime = 1;
    player.pause();
    player.changeRate(0.5);
    expect(player.position).toBe(2);
    expect(vi.getTimerCount()).toBe(0);
    expect(AudioClock.latest.sources).toHaveLength(2);
    for (const invalid of [0, -1, NaN, Infinity]) player.changeRate(invalid);
    expect(player.position).toBe(2);
  });
  it("LTS-065 seeking clamps at both ends and schedules from the requested source position", async () => {
    await player.load(slices, loadClip);
    player.seek(-5);
    expect(player.position).toBe(0);
    player.seek(3);
    expect(player.position).toBe(3);
    expect(AudioClock.latest.sources.at(-1)!.start).toHaveBeenLastCalledWith(
      0,
      7,
      2,
    );
    player.seek(5);
    expect(player.position).toBe(4);
    vi.advanceTimersByTime(30);
    expect(onEnd).toHaveBeenCalledOnce();
  });
  it("LTS-015 a canceled slow load cannot replace or resume the new playback", async () => {
    let resolve!: (value: AudioClip) => void;
    const old = player.load(
      slices,
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    await Promise.resolve();
    await player.load([slices[1]], loadClip);
    resolve(clip);
    await old;
    expect(AudioClock.latest.sources).toHaveLength(1);
    expect(AudioClock.latest.sources[0].start).toHaveBeenCalledWith(0, 5, 4);
  });
  it("missing recordings fail with recovery guidance and do not start playback", async () => {
    await expect(player.load(slices, async () => undefined)).rejects.toThrow(
      "Restore its backup",
    );
    expect(AudioClock.latest.sources).toHaveLength(0);
    expect(vi.getTimerCount()).toBe(0);
  });
  it("LTS-049 LTS-062 LTS-150 WAV export applies slice ordering, speed and gain, caching shared sources", async () => {
    const wav = await renderTimeline([slices[1], slices[0]], loadClip);
    const data = new DataView(await wav.arrayBuffer());
    expect(data.getUint32(24, true)).toBe(16000);
    expect(data.byteLength).toBe(44 + 4 * 16000 * 2);
    expect(data.getInt16(44, true)).toBeCloseTo(0.125 * 32767, -1);
    expect(data.getInt16(44 + 2 * 16000 * 2, true)).toBeCloseTo(
      0.25 * 32767,
      -1,
    );
    expect(loadClip).toHaveBeenCalledOnce();
    expect(AudioClock.latest.close).toHaveBeenCalledOnce();
  });
  it("export closes its audio context even if the source is missing", async () => {
    await expect(renderTimeline(slices, async () => undefined)).rejects.toThrow(
      "missing",
    );
    expect(AudioClock.latest.close).toHaveBeenCalledOnce();
  });
});

it("removes silence inside broad model word estimates in both scheduled playback and exported audio", async () => {
  const audio = new Float32Array(32000);
  audio.fill(0.1, 3200, 11200);
  audio.fill(0.1, 24000, 28800);
  class PausedClock extends AudioClock {
    decodeAudioData = vi.fn(async () => ({
      duration: 2,
      sampleRate: 16000,
      getChannelData: () => audio,
    }));
  }
  vi.stubGlobal("AudioContext", PausedClock);
  const slice = {
    clipId: "a",
    start: 0,
    end: 2,
    rate: 1,
    gain: 1,
    textStart: 0,
    textEnd: 5,
    omitSilences: true,
  };
  await player.load([slice], loadClip);
  expect(AudioClock.latest.sources).toHaveLength(2);
  expect(AudioClock.latest.sources[1].start.mock.calls[0][0]).toBeCloseTo(0.56);
  const trimmed = await renderTimeline([slice], loadClip);
  const original = await renderTimeline(
    [{ ...slice, omitSilences: false }],
    loadClip,
  );
  expect((trimmed.size - 44) / 32000).toBeCloseTo(0.92, 3);
  expect((original.size - 44) / 32000).toBe(2);
});

it("seeks by transcript word without losing paused state or using unedited source seconds", async () => {
  await player.load(slices, loadClip);
  player.pause();
  expect(player.seekToWord(4)).toBe(true);
  expect(player.position).toBe(2);
  expect(onPosition).toHaveBeenLastCalledWith(4, 7, 2);
  expect(vi.getTimerCount()).toBe(0);
  expect(player.seekToWord(100)).toBe(false);
  player.resume();
  expect(AudioClock.latest.sources.at(-1)!.start).toHaveBeenLastCalledWith(0, 5, 4);
  expect(player.seekToWord(0)).toBe(true);
  expect(vi.getTimerCount()).toBe(1);
});

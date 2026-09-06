import { afterEach, expect, it, vi } from "vitest";
import { BrowseClock } from "./browse";
afterEach(() => vi.useRealTimers());
it("plays after half a second, echoes after playback, and advances on the native run clock", async () => {
  vi.useFakeTimers();
  const events: string[] = [];
  const clock = new BrowseClock();
  clock.start({ mode: "run", headphonesConnected: true, rate: 1, duration: .2,
    play: async () => { events.push("audio"); }, echo: () => events.push("echo"), next: () => events.push("next") });
  await vi.advanceTimersByTimeAsync(499); expect(events).toEqual([]);
  await vi.advanceTimersByTimeAsync(501); expect(events).toEqual(["audio", "echo"]);
  await vi.advanceTimersByTimeAsync(1000); expect(events).toEqual(["audio", "echo", "next"]);
});
it("walk waits three seconds, speeds up with playback rate, and remains visual without headphones", async () => {
  vi.useFakeTimers();
  const play = vi.fn(), echo = vi.fn(), next = vi.fn();
  const clock = new BrowseClock();
  clock.start({ mode: "walk", headphonesConnected: false, rate: 2, duration: .2, play, echo, next });
  await vi.advanceTimersByTimeAsync(1499); expect(next).not.toHaveBeenCalled();
  await vi.advanceTimersByTimeAsync(1); expect(next).toHaveBeenCalledOnce();
  expect(play).not.toHaveBeenCalled(); expect(echo).not.toHaveBeenCalled();
});
it("cancels timers and late playback completions when a selection or session changes", async () => {
  vi.useFakeTimers();
  let finish!: () => void;
  const echo = vi.fn(), next = vi.fn();
  const clock = new BrowseClock();
  clock.start({ mode: "walk", headphonesConnected: true, rate: 1, duration: 2,
    play: () => new Promise<void>((resolve) => { finish = resolve; }), echo, next });
  await vi.advanceTimersByTimeAsync(500); clock.stop(); finish();
  await vi.advanceTimersByTimeAsync(10000);
  expect(echo).not.toHaveBeenCalled(); expect(next).not.toHaveBeenCalled();
});

import { listPreviewSeconds } from "./browse";
it("uses ten-second walk previews but ends short run previews at their recorded duration", () => {
  expect(listPreviewSeconds("walk", 3, 1)).toBe(10);
  expect(listPreviewSeconds("run", 3, 1)).toBe(3);
  expect(listPreviewSeconds("run", 20, 2)).toBe(5);
  expect(listPreviewSeconds("run", 0, 1)).toBe(1);
});

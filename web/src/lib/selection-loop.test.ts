import { afterEach, expect, it, vi } from "vitest";
import { SelectionLoop } from "./selection-loop";

afterEach(() => vi.useRealTimers());
it("repeats original selection audio one second after its actual completion", async () => {
  vi.useFakeTimers();
  let finish!: () => void;
  const play = vi.fn(
    () =>
      new Promise<void>((resolve) => {
        finish = resolve;
      }),
  );
  const loop = new SelectionLoop();
  loop.start(play);
  expect(play).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(10000);
  expect(play).toHaveBeenCalledTimes(1);
  finish();
  await vi.advanceTimersByTimeAsync(999);
  expect(play).toHaveBeenCalledTimes(1);
  await vi.advanceTimersByTimeAsync(1);
  expect(play).toHaveBeenCalledTimes(2);
  loop.stop();
});
it("a cleared or replaced selection cannot restart from an old audio completion", async () => {
  vi.useFakeTimers();
  let finish!: () => void;
  const old = vi.fn(
    () =>
      new Promise<void>((resolve) => {
        finish = resolve;
      }),
  );
  const next = vi.fn(async () => {});
  const loop = new SelectionLoop();
  loop.start(old);
  loop.stop();
  finish();
  await vi.advanceTimersByTimeAsync(2000);
  expect(old).toHaveBeenCalledTimes(1);
  loop.start(next);
  await vi.advanceTimersByTimeAsync(500);
  loop.stop();
  await vi.advanceTimersByTimeAsync(2000);
  expect(next).toHaveBeenCalledTimes(1);
});

import type { BrowseClockOptions } from "../interfaces/browse";

/** Own all delayed work for one native-style word review cycle. */
export class BrowseClock {
  private timers: ReturnType<typeof setTimeout>[] = [];
  private generation = 0;

  stop(): void {
    this.generation += 1;
    this.timers.forEach(clearTimeout);
    this.timers = [];
  }

  /** Advance from the cycle start, so recording length cannot slow the run clock. */
  start(options: BrowseClockOptions): void {
    this.stop();
    const generation = this.generation;
    const rate = Math.max(0.2, options.rate);
    const schedule = (delay: number, callback: () => void) => {
      this.timers.push(
        setTimeout(() => {
          if (this.generation === generation) callback();
        }, delay),
      );
    };
    // ** IMPORTANT **: Keep in sync with Entry.swift walk/run timing constants.
    const period =
      options.mode === "run"
        ? 2
        : Math.max(3, 2 * options.duration - 0.5, options.duration + 1.5);
    schedule((1000 * period) / rate, options.next);
    if (!options.headphonesConnected) return;
    schedule(500 / rate, () => {
      const started = Date.now();
      // Wait for the actual word before echoing; native timers could cut long words off.
      void options
        .play()
        .then(() => {
          if (this.generation !== generation) return;
          schedule(
            Math.max(0, 500 / rate - (Date.now() - started)),
            options.echo,
          );
        })
        .catch((cause) => options.onError?.(cause));
    });
  }
}

/** Entry-list runs preview up to ten seconds; allow one second to announce an empty entry. */
export function listPreviewSeconds(
  mode: "walk" | "run",
  duration: number,
  rate: number,
): number {
  if (mode === "walk") return 10 / Math.max(0.2, rate);
  if (duration <= 0) return 1;
  return Math.min(10, duration) / Math.max(0.2, rate);
}

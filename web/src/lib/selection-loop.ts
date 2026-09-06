/** Own the native selection repeat: original audio, then one second of quiet. */
export class SelectionLoop {
  private generation = 0;
  private timer?: ReturnType<typeof setTimeout>;

  start(play: () => Promise<void>, onError?: (cause: unknown) => void): void {
    this.stop();
    const generation = this.generation;
    const repeat = async () => {
      try {
        await play();
        if (generation !== this.generation) return;
        this.timer = setTimeout(() => void repeat(), 1000);
      } catch (cause) {
        if (generation === this.generation) onError?.(cause);
      }
    };
    void repeat();
  }

  stop(): void {
    ++this.generation;
    clearTimeout(this.timer);
  }
}

import type { QueuedNotification } from "../interfaces/notification";

/** FIFO feedback with explicit indefinite notices; clearing owns and cancels the active timer. */
export class NotificationQueue {
  private items: QueuedNotification[] = [];
  private active = false;
  private timer?: ReturnType<typeof setTimeout>;
  constructor(private show: (text: string) => void) {}
  push(text: string, duration?: number): void {
    this.items.push({ text, duration });
    if (!this.active) this.next();
  }
  private next(): void {
    const item = this.items.shift();
    this.active = Boolean(item);
    this.show(item?.text ?? "");
    if (item?.duration !== undefined)
      this.timer = setTimeout(() => this.next(), item.duration);
  }
  clear(): void {
    clearTimeout(this.timer);
    this.items = [];
    this.active = false;
    this.show("");
  }
}

/** Native anticipation cues are tied to recognition activity, not slow final-model completion. */
export class PauseSuggestions {
  private sentence?: ReturnType<typeof setTimeout>;
  private paragraph?: ReturnType<typeof setTimeout>;
  constructor(private show: (kind: "sentence" | "paragraph") => void) {}
  heard(): void {
    this.stop();
    this.sentence = setTimeout(() => this.show("sentence"), 4000);
    this.paragraph = setTimeout(() => this.show("paragraph"), 7000);
  }
  stop(): void {
    clearTimeout(this.sentence);
    clearTimeout(this.paragraph);
  }
}

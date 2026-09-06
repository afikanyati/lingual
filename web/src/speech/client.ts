import type { Transcript } from "../interfaces/timeline";
import type { SpeechRequest, SpeechResponse } from "../interfaces/speech";

interface PendingRequest {
  resolve: (message: SpeechResponse) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}
/** Own one worker and reject all in-flight requests if it crashes or exceeds its deadline. */
export class SpeechClient {
  private worker?: Worker;
  private nextId = 0;
  private pending = new Map<number, PendingRequest>();
  onProgress?: (value: number, file: string) => void;

  private getWorker(): Worker {
    if (this.worker) return this.worker;
    const worker = new Worker(new URL("./worker.ts", import.meta.url), {
      type: "module",
    });
    worker.onmessage = ({ data }: MessageEvent<SpeechResponse>) => {
      const pending = this.pending.get(data.id);
      if (!pending) return;
      if (data.type === "progress") {
        this.onProgress?.(data.progress ?? 0, data.message ?? "");
        return;
      }
      clearTimeout(pending.timer);
      this.pending.delete(data.id);
      if (data.type === "error")
        pending.reject(new Error(data.message || "Transcription failed."));
      else pending.resolve(data);
    };
    worker.onerror = () =>
      this.dispose(
        "The speech engine stopped. Your saved audio can be transcribed again.",
      );
    this.worker = worker;
    return worker;
  }
  private request(
    type: SpeechRequest["type"],
    audio?: Float32Array,
  ): Promise<SpeechResponse> {
    const worker = this.getWorker();
    const id = ++this.nextId;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () =>
          this.dispose(
            "The speech engine timed out. Check your connection for the model download, then retry.",
          ),
        180_000,
      );
      this.pending.set(id, { resolve, reject, timer });
      worker.postMessage({ id, type, audio } satisfies SpeechRequest);
    });
  }
  async load(): Promise<void> {
    await this.request("load");
  }
  async transcribe(audio: Float32Array): Promise<Transcript> {
    const result = await this.request("transcribe", audio);
    return { text: result.text ?? "", words: result.words ?? [] };
  }
  dispose(message = "Speech engine closed."): void {
    this.worker?.terminate();
    this.worker = undefined;
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error(message));
    }
    this.pending.clear();
  }
}

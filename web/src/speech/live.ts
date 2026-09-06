import type { ServerMessage } from "@lichess-org/vosk-browser/dist/vosk.interfaces";

interface Utterance {
  replies: number;
  completed: string[];
  closing: boolean;
  resolve?: (text: string) => void;
  reject?: (error: Error) => void;
  timer?: ReturnType<typeof setTimeout>;
}

/** Stream PCM to local Vosk. Each recording chunk has its own recognizer and final-result barrier. */
export class LiveSpeechClient {
  private worker?: Worker;
  private utterances = new Map<string, Utterance>();
  private loading?: Promise<void>;
  private loaded?: () => void;
  private loadFailed?: (error: Error) => void;
  private loadTimer?: ReturnType<typeof setTimeout>;
  onPartial?: (id: string, text: string) => void;
  onError?: (error: Error) => void;

  load(): Promise<void> {
    if (this.loading) return this.loading;
    const root = new URL(
      `${import.meta.env.BASE_URL}speech/vosk-0.0.3/`,
      location.origin,
    );
    this.worker = new Worker(new URL("vosk.worker.js", root), {
      type: "module",
    });
    this.worker.onmessage = ({ data }: MessageEvent<ServerMessage>) =>
      this.receive(data);
    this.worker.onerror = () =>
      this.dispose(
        "Live speech recognition stopped. Your original recording is saved.",
      );
    this.loading = new Promise((resolve, reject) => {
      this.loaded = resolve;
      this.loadFailed = reject;
      this.loadTimer = setTimeout(
        () => this.dispose("Live speech model download timed out."),
        180000,
      );
    });
    this.worker.postMessage({
      action: "load",
      modelUrl: new URL("models/en-us-0.15.tar.gz", root).href,
      wasmUrl: new URL("vosk.wasm", root).href,
    });
    return this.loading;
  }

  /** Copy and scale normalized capture samples; the original buffer remains owned by the recording. */
  accept(id: string, audio: Float32Array): void {
    // A crashed preview engine must never prevent the microphone from saving its remaining audio.
    if (!this.worker) return;
    let utterance = this.utterances.get(id);
    if (!utterance) {
      utterance = { replies: 0, completed: [], closing: false };
      this.utterances.set(id, utterance);
      this.worker.postMessage({
        action: "create",
        recognizerId: id,
        sampleRate: 16000,
      });
    }
    if (utterance.closing) return;
    utterance.replies++;
    const data = Float32Array.from(audio, (sample) => sample * 32768);
    this.worker.postMessage(
      { action: "audioChunk", recognizerId: id, data, sampleRate: 16000 },
      [data.buffer],
    );
  }

  /** FinalResult frees the recognizer in the pinned worker. Wait past all preceding audio responses. */
  finish(id: string): Promise<string> {
    const utterance = this.utterances.get(id);
    if (!utterance) return Promise.resolve("");
    utterance.closing = true;
    utterance.replies++;
    const result = new Promise<string>((resolve, reject) => {
      utterance.resolve = resolve;
      utterance.reject = reject;
      utterance.timer = setTimeout(
        () =>
          this.dispose(
            "Live speech could not keep up. Your recording is saved for retry.",
          ),
        30000,
      );
    });
    this.worker!.postMessage({
      action: "retrieveFinalResult",
      recognizerId: id,
    });
    return result;
  }

  private receive(message: ServerMessage): void {
    if (!message) return; // The upstream create acknowledgement has no payload.
    if (message.event === "load") {
      if (!message.result) {
        this.dispose("Live speech model could not load.");
        return;
      }
      clearTimeout(this.loadTimer);
      this.loaded?.();
      this.loaded = undefined;
      this.loadFailed = undefined;
      this.worker?.postMessage({ action: "set", key: "logLevel", value: -1 });
      return;
    }
    if (message.event === "error") {
      this.dispose(message.error);
      return;
    }
    const utterance = this.utterances.get(message.recognizerId);
    if (!utterance) return; // Ignore stale responses after disposal.
    utterance.replies--;
    if (message.event === "result" && message.result.text)
      utterance.completed.push(message.result.text);
    const partial =
      message.event === "partialresult" ? message.result.partial : "";
    const text = [...utterance.completed, partial].filter(Boolean).join(" ");
    this.onPartial?.(message.recognizerId, text);
    if (!utterance.closing || utterance.replies !== 0) return;
    clearTimeout(utterance.timer);
    this.utterances.delete(message.recognizerId);
    utterance.resolve?.(text);
  }

  dispose(message = "Live speech engine closed."): void {
    const error = new Error(message);
    clearTimeout(this.loadTimer);
    this.loadFailed?.(error);
    this.loadFailed = undefined;
    this.loaded = undefined;
    this.loading = undefined;
    this.worker?.terminate();
    this.worker = undefined;
    for (const utterance of this.utterances.values()) {
      clearTimeout(utterance.timer);
      utterance.reject?.(error);
    }
    this.utterances.clear();
    this.onError?.(error);
  }
}

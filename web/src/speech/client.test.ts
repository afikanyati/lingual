import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SpeechClient } from "./client";
import type { SpeechResponse } from "../interfaces/speech";

class ControlledWorker {
  static instances: ControlledWorker[] = [];
  onmessage?: (event: { data: SpeechResponse }) => void;
  onerror?: () => void;
  postMessage = vi.fn();
  terminate = vi.fn();
  constructor() {
    ControlledWorker.instances.push(this);
  }
  respond(data: SpeechResponse) {
    this.onmessage?.({ data });
  }
}
let client: SpeechClient;
beforeEach(() => {
  vi.useFakeTimers();
  ControlledWorker.instances = [];
  vi.stubGlobal("Worker", ControlledWorker);
  client = new SpeechClient();
});
afterEach(() => {
  client.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});
const worker = () => ControlledWorker.instances.at(-1)!;

describe("speech worker reliability behind Lingual listening", () => {
  it("LTS-015 associates out-of-order results with their originating request and ignores duplicate/stale replies", async () => {
    const first = client.transcribe(new Float32Array([1]));
    const second = client.transcribe(new Float32Array([2]));
    worker().respond({
      id: 2,
      type: "result",
      text: "two",
      words: [{ text: "two", start: 0.2, end: 0.5 }],
    });
    worker().respond({ id: 1, type: "result", text: "one" });
    worker().respond({ id: 1, type: "result", text: "duplicate" });
    expect(await first).toEqual({ text: "one", words: [] });
    expect(await second).toEqual({
      text: "two",
      words: [{ text: "two", start: 0.2, end: 0.5 }],
    });
    expect(vi.getTimerCount()).toBe(0);
    expect(ControlledWorker.instances).toHaveLength(1);
  });
  it("LTS-089 worker errors reject only their request once", async () => {
    const failed = client.load();
    const passed = client.load();
    const rejected = expect(failed).rejects.toThrow("Unavailable");
    worker().respond({ id: 1, type: "error", message: "Unavailable" });
    worker().respond({ id: 1, type: "error", message: "duplicate" });
    worker().respond({ id: 2, type: "ready" });
    await rejected;
    await passed;
    expect(vi.getTimerCount()).toBe(0);
  });
  it("progress does not falsely complete a model download", async () => {
    client.onProgress = vi.fn();
    const promise = client.load();
    const done = vi.fn();
    void promise.then(done);
    worker().respond({
      id: 1,
      type: "progress",
      progress: 50,
      message: "weights",
    });
    await Promise.resolve();
    expect(done).not.toHaveBeenCalled();
    expect(client.onProgress).toHaveBeenCalledWith(50, "weights");
    worker().respond({ id: 1, type: "ready" });
    await promise;
    expect(vi.getTimerCount()).toBe(0);
  });
  it("a crashed worker rejects all requests and a retry creates a fresh worker", async () => {
    const first = client.load();
    const second = client.transcribe(new Float32Array(2));
    const failures = Promise.all([
      expect(first).rejects.toThrow("stopped"),
      expect(second).rejects.toThrow("stopped"),
    ]);
    const old = worker();
    old.onerror?.();
    await failures;
    expect(old.terminate).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
    const retry = client.load();
    expect(ControlledWorker.instances).toHaveLength(2);
    old.respond({ id: 1, type: "ready" });
    worker().respond({ id: 3, type: "ready" });
    await retry;
  });
  it("a stalled request times out, frees all timers and permits a retry", async () => {
    const promise = client.load();
    const failure = expect(promise).rejects.toThrow("timed out");
    vi.advanceTimersByTime(180000);
    await failure;
    expect(worker().terminate).toHaveBeenCalledOnce();
    const retry = client.load();
    worker().respond({ id: 2, type: "ready" });
    await retry;
    expect(vi.getTimerCount()).toBe(0);
  });
  it("disposing rejects in-flight transcription rather than losing it silently", async () => {
    const promise = client.transcribe(new Float32Array(2));
    const failure = expect(promise).rejects.toThrow("closed");
    client.dispose();
    await failure;
    expect(vi.getTimerCount()).toBe(0);
  });
});

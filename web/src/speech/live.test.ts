import { afterEach, expect, it, vi } from "vitest";
import { LiveSpeechClient } from "./live";

class FakeWorker {
  static latest: FakeWorker;
  onmessage?: (event: { data: unknown }) => void;
  onerror?: () => void;
  messages: any[] = [];
  constructor() {
    FakeWorker.latest = this;
  }
  postMessage(message: any) {
    this.messages.push(message);
  }
  terminate = vi.fn();
  send(data: unknown) {
    this.onmessage?.({ data });
  }
}
afterEach(() => vi.unstubAllGlobals());
async function setup() {
  vi.stubGlobal("Worker", FakeWorker);
  vi.stubGlobal("location", { origin: "http://localhost" });
  const client = new LiveSpeechClient();
  const loading = client.load();
  const worker = FakeWorker.latest;
  worker.send({ event: "load", result: true });
  await loading;
  return { client, worker };
}
it("publishes gray hypotheses before a chunk finishes and resolves only its matching final reply", async () => {
  const { client, worker } = await setup();
  const preview = vi.fn();
  client.onPartial = preview;
  const audio = new Float32Array([0.1, -0.1]);
  client.accept("a", audio);
  const result = client.finish("a");
  worker.send({
    event: "partialresult",
    recognizerId: "a",
    result: { partial: "play" },
  });
  expect(preview).toHaveBeenCalledWith("a", "play");
  worker.send({
    event: "result",
    recognizerId: "a",
    result: { text: "play note" },
  });
  expect(await result).toBe("play note");
  expect(audio[0]).toBeCloseTo(0.1); // feeding Vosk must not detach/mutate the recording
  expect(
    worker.messages.find((m) => m.action === "audioChunk").data[0],
  ).toBeCloseTo(3276.8, 2);
  client.dispose();
});
it("keeps successive utterances separate and combines endpoint results without losing words", async () => {
  const { client, worker } = await setup();
  client.accept("a", new Float32Array(2));
  worker.send({
    event: "result",
    recognizerId: "a",
    result: { text: "first" },
  });
  const first = client.finish("a");
  client.accept("b", new Float32Array(2));
  worker.send({
    event: "partialresult",
    recognizerId: "b",
    result: { partial: "next" },
  });
  worker.send({ event: "result", recognizerId: "a", result: { text: "last" } });
  expect(await first).toBe("first last");
  const second = client.finish("b");
  worker.send({ event: "result", recognizerId: "b", result: { text: "next" } });
  expect(await second).toBe("next");
  client.dispose();
});
it("rejects load failures and unfinished utterances when the worker crashes", async () => {
  vi.stubGlobal("Worker", FakeWorker);
  vi.stubGlobal("location", { origin: "http://localhost" });
  const failed = new LiveSpeechClient();
  const loading = failed.load();
  FakeWorker.latest.send({ event: "error", error: "Model unavailable" });
  await expect(loading).rejects.toThrow("Model unavailable");
  const { client, worker } = await setup();
  client.accept("a", new Float32Array(2));
  const result = client.finish("a");
  worker.onerror?.();
  await expect(result).rejects.toThrow("stopped");
});

import { describe, it, expect, vi, afterEach } from "vitest";
import { MicrophoneCapture } from "./capture";

afterEach(() => vi.unstubAllGlobals());
describe("microphone permissions and cancellation", () => {
  it("releases a microphone granted after stop without starting an audio context", async () => {
    let grant!: (stream: MediaStream) => void;
    const stop = vi.fn();
    vi.stubGlobal("navigator", {
      mediaDevices: {
        getUserMedia: () =>
          new Promise((resolve) => {
            grant = resolve;
          }),
      },
    });
    const capture = new MicrophoneCapture({
      onChunk: vi.fn(),
      onLevel: vi.fn(),
      onInterrupted: vi.fn(),
    });
    const starting = capture.start();
    await capture.stop();
    grant({ getTracks: () => [{ stop }] } as unknown as MediaStream);
    await starting;
    expect(stop).toHaveBeenCalledOnce();
  });
  it("surfaces permission denial and permits a fresh attempt", async () => {
    const getUserMedia = vi
      .fn()
      .mockRejectedValue(new Error("Permission denied"));
    vi.stubGlobal("navigator", { mediaDevices: { getUserMedia } });
    const capture = new MicrophoneCapture({
      onChunk: vi.fn(),
      onLevel: vi.fn(),
      onInterrupted: vi.fn(),
    });
    await expect(capture.start()).rejects.toThrow("Permission denied");
    await expect(capture.start()).rejects.toThrow("Permission denied");
    expect(getUserMedia).toHaveBeenCalledTimes(2);
  });
});

it("drains a final compatibility buffer and releases every resource on stop", async () => {
  const track = { stop: vi.fn(), addEventListener: vi.fn() };
  const fallback = {
    connect: vi.fn(),
    disconnect: vi.fn(),
    onaudioprocess: null as ((event: any) => void) | null,
  };
  const source = { connect: vi.fn(), disconnect: vi.fn() };
  const close = vi.fn();
  vi.stubGlobal("navigator", {
    mediaDevices: {
      getUserMedia: async () => ({
        getTracks: () => [track],
        getAudioTracks: () => [track],
      }),
    },
  });
  vi.stubGlobal(
    "AudioContext",
    class {
      state = "running";
      sampleRate = 48000;
      destination = {};
      audioWorklet = {
        addModule: async () => {
          throw new Error("Worklet unavailable");
        },
      };
      resume = async () => {};
      close = close;
      createMediaStreamSource = () => source;
      createGain = () => ({ gain: { value: 0 }, connect: vi.fn() });
      createScriptProcessor = () => fallback;
    },
  );
  const onChunk = vi.fn();
  const capture = new MicrophoneCapture({
    onChunk,
    onLevel: vi.fn(),
    onInterrupted: vi.fn(),
  });
  await capture.start();
  const stopping = capture.stop();
  // This callback was already in flight when the user pressed Stop.
  fallback.onaudioprocess?.({
    inputBuffer: { getChannelData: () => new Float32Array(4096).fill(0.1) },
  });
  await stopping;
  expect(onChunk).toHaveBeenCalledOnce();
  expect(onChunk.mock.calls[0][0]).toHaveLength(1365);
  expect(track.stop).toHaveBeenCalledOnce();
  expect(source.disconnect).toHaveBeenCalledOnce();
  expect(close).toHaveBeenCalledOnce();
  expect(fallback.onaudioprocess).toBeNull();
});

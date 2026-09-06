import { expect, type Page } from "@playwright/test";

/** Replace only device/model boundaries; React, recording queues, storage and command handling stay real. */
export async function installSpeechHardware(page: Page) {
  await page.addInitScript(() => {
    const hardware = {
      phrases: new Map<number, string>(),
      signal: 0.1,
      liveText: "",
      deferWhisper: false,
      whisperReplies: [] as (() => void)[],
      preview(text: string) {
        this.liveText = text;
        this.process?.({
          inputBuffer: {
            getChannelData: () => new Float32Array(16000).fill(this.signal),
          },
        });
      },
      finishWhisper() {
        this.whisperReplies.splice(0).forEach((reply) => reply());
      },
      process: undefined as
        | ((event: {
            inputBuffer: { getChannelData: () => Float32Array };
          }) => void)
        | undefined,
      utterances: [] as SpeechSynthesisUtterance[],
      paused: false,
      stoppedTracks: 0,
      playbackStarts: 0,
      speechCancellations: 0,
      outputLabel: "Default - MacBook Pro Speakers",
      hideOutputUntilPermission: false,
      microphoneGranted: false,
      setOutput(label: string) {
        this.outputLabel = label;
        navigator.mediaDevices.dispatchEvent(new Event("devicechange"));
      },
      say(text: string) {
        // Tag synthetic PCM so command clips skipped by Whisper cannot shift subsequent transcripts.
        this.phrases.set(Math.round(this.signal * 1000), text);
        this.liveText = text;
        this.process?.({
          inputBuffer: {
            getChannelData: () => new Float32Array(16000).fill(this.signal),
          },
        });
        this.process?.({
          inputBuffer: { getChannelData: () => new Float32Array(16000) },
        });
        this.signal += 0.001;
      },
      boundary(index: number, length: number) {
        this.utterances.at(-1)?.onboundary?.({
          name: "word",
          charIndex: index,
          charLength: length,
        } as SpeechSynthesisEvent);
      },
      finishEcho() {
        this.utterances.at(-1)?.onend?.({} as SpeechSynthesisEvent);
      },
    };
    Object.assign(window, { lingualHardware: hardware });
    class ModelWorker {
      onmessage?: (event: { data: unknown }) => void;
      live = new Map<string, string>();
      postMessage(request: {
        id: number;
        type: string;
        audio?: Float32Array;
        action?: string;
        recognizerId?: string;
      }) {
        if (request.action) {
          const recognizerId = request.recognizerId!;
          let response: unknown;
          if (request.action === "load")
            response = { event: "load", result: true };
          if (request.action === "audioChunk") {
            this.live.set(recognizerId, hardware.liveText);
            response = {
              event: "partialresult",
              recognizerId,
              result: { partial: hardware.liveText },
            };
          }
          if (request.action === "retrieveFinalResult") {
            response = {
              event: "result",
              recognizerId,
              result: { text: this.live.get(recognizerId) ?? "" },
            };
            this.live.delete(recognizerId);
          }
          if (response)
            queueMicrotask(() => this.onmessage?.({ data: response }));
          return;
        }
        const text =
          request.type === "transcribe"
            ? (hardware.phrases.get(
                Math.round(
                  (request.audio?.find((value) => value > 0) ?? 0) * 1000,
                ),
              ) ?? "")
            : "";
        const words = text
          .split(/\s+/)
          .filter(Boolean)
          .map((text, index) => ({
            text,
            start: index * 0.1,
            end: (index + 1) * 0.1,
          }));
        const respond = () =>
          this.onmessage?.({
            data: {
              id: request.id,
              type: request.type === "load" ? "ready" : "result",
              text,
              words,
            },
          });
        if (request.type === "transcribe" && hardware.deferWhisper)
          hardware.whisperReplies.push(respond);
        else queueMicrotask(respond);
      }
      terminate() {}
    }
    Object.defineProperty(window, "Worker", { value: ModelWorker });
    const NativeAudioContext = window.AudioContext;
    class CaptureContext extends NativeAudioContext {
      /** Observe real scheduled audio so tests cannot miss a short word between DOM polling intervals. */
      createBufferSource() {
        const source = super.createBufferSource();
        const start = source.start.bind(source);
        source.start = (
          ...args: Parameters<AudioBufferSourceNode["start"]>
        ) => {
          hardware.playbackStarts += 1;
          start(...args);
        };
        return source;
      }
      constructor(options?: AudioContextOptions) {
        super({ sampleRate: 16000, ...options });
        Object.defineProperty(this, "audioWorklet", {
          value: {
            addModule: async () => {
              throw new Error("Deterministic compatibility capture");
            },
          },
        });
      }
      createMediaStreamSource() {
        return {
          connect() {},
          disconnect() {},
        } as unknown as MediaStreamAudioSourceNode;
      }
      createScriptProcessor() {
        return {
          set onaudioprocess(callback: typeof hardware.process) {
            hardware.process = callback;
          },
          connect() {},
          disconnect() {},
        } as unknown as ScriptProcessorNode;
      }
    }
    Object.defineProperty(window, "AudioContext", { value: CaptureContext });
    Object.defineProperty(navigator.mediaDevices, "enumerateDevices", {
      configurable: true,
      value: async () => [
        {
          kind: "audiooutput",
          deviceId: "default",
          groupId: "system-output",
          label:
            hardware.hideOutputUntilPermission && !hardware.microphoneGranted
              ? ""
              : hardware.outputLabel,
        },
      ],
    });
    Object.defineProperty(navigator.mediaDevices, "getUserMedia", {
      value: async () => {
        hardware.microphoneGranted = true;
        const track = new EventTarget();
        Object.assign(track, { stop: () => hardware.stoppedTracks++ });
        return { getTracks: () => [track], getAudioTracks: () => [track] };
      },
    });
    Object.defineProperty(window, "SpeechSynthesisUtterance", {
      value: class {
        text: string;
        constructor(text: string) {
          this.text = text;
        }
      },
    });
    Object.defineProperty(window, "speechSynthesis", {
      value: {
        speaking: false,
        getVoices: () => [
          {
            localService: true,
            lang: "en-US",
            voiceURI: "test",
            name: "Test voice",
          },
        ],
        speak(utterance: SpeechSynthesisUtterance) {
          this.speaking = true;
          hardware.utterances.push(utterance);
        },
        pause() {
          hardware.paused = true;
        },
        resume() {
          hardware.paused = false;
        },
        cancel() {
          hardware.speechCancellations++;
          this.speaking = false;
        },
        addEventListener() {},
        removeEventListener() {},
      },
    });
  });
}
export async function say(page: Page, text: string) {
  await page.evaluate(
    (text) => (window as any).lingualHardware.say(text),
    text,
  );
}
export async function select(page: Page, start: number, end: number) {
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  await page.getByRole("textbox", { name: "Entry text" }).evaluate(
    (element: HTMLTextAreaElement, range) => {
      element.focus();
      element.setSelectionRange(range.start, range.end);
      element.dispatchEvent(new Event("select", { bubbles: true }));
      document.dispatchEvent(new Event("selectionchange"));
    },
    { start, end },
  );
}
export async function command(page: Page, label: string) {
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page.getByLabel("Find a voice action").fill(label);
  await page
    .locator(".command-palette")
    .getByRole("button", { name: `${label} ↗`, exact: true })
    .click();
}

/** Dictate through the production capture, inference queue and persistence path. */
export async function record(page: Page, text: string, replacement = false) {
  const enable = page.getByRole("button", {
    name: "Enable voice",
    exact: true,
  });
  if (await enable.isVisible()) await enable.click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, text);
  const transcript = page.locator(
    `textarea[aria-label="${replacement ? "Replacement text" : "Entry text"}"]`,
  );
  await expect(transcript).toHaveValue(text);
  await page.getByRole("button", { name: /Stop listening/i }).click();
  await expect(
    page.getByRole("button", { name: "Resume entry", exact: true }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
}

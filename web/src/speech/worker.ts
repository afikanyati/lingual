/// <reference lib="webworker" />
import {
  env,
  pipeline,
  type AutomaticSpeechRecognitionPipeline,
} from "@huggingface/transformers";
import type { SpeechRequest, SpeechResponse } from "../interfaces/speech";
import { speechAssetURLs } from "./assets";
import manifest from "../config/speech-assets.json";

// The production build includes model files and the matching runtime. No external inference/CDN request is needed.
const assets = speechAssetURLs(import.meta.env.BASE_URL, self.location.origin);
env.allowLocalModels = true;
env.allowRemoteModels = false;
env.localModelPath = assets.models;
// Reuse downloaded weights across visits where the browser supports Cache Storage.
env.useBrowserCache = typeof caches !== "undefined";
env.backends.onnx.wasm!.wasmPaths = assets.runtime;
// One worker thread avoids requiring cross-origin isolation headers on a static host.
env.backends.onnx.wasm!.numThreads = 1;
let recognizer: AutomaticSpeechRecognitionPipeline | undefined;
const send = (message: SpeechResponse) => self.postMessage(message);
self.onmessage = async ({ data }: MessageEvent<SpeechRequest>) => {
  try {
    if (!recognizer) {
      recognizer = await pipeline<"automatic-speech-recognition">(
        "automatic-speech-recognition",
        manifest.model,
        {
          device: "wasm",
          dtype: "q8",
          progress_callback: (progress) => {
            if ("progress" in progress)
              send({
                id: data.id,
                type: "progress",
                progress: progress.progress,
                message: progress.file,
              });
          },
        },
      );
    }
    if (data.type === "load") {
      send({ id: data.id, type: "ready" });
      return;
    }
    if (!data.audio?.length) throw new Error("No audio samples were captured.");
    // Preserve decoder punctuation. Word alignment may attach marks to a word or emit a separate chunk;
    // transcriptPassage preserves both forms as text without assigning standalone marks invented audio.
    const result = await recognizer(data.audio, {
      chunk_length_s: 30,
      stride_length_s: 5,
      return_timestamps: "word",
    });
    const output = Array.isArray(result) ? result[0] : result;
    const words = (output.chunks ?? []).map((chunk) => ({
      text: chunk.text,
      start: chunk.timestamp[0] ?? 0,
      end: chunk.timestamp[1] ?? data.audio!.length / 16000,
    }));
    send({ id: data.id, type: "result", text: output.text.trim(), words });
  } catch (error) {
    recognizer = undefined;
    send({
      id: data.id,
      type: "error",
      message: error instanceof Error ? error.message : String(error),
    });
  }
};

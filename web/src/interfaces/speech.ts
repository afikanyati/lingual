import type { Command } from "../enums/command";
import type { TranscriptWord } from "./timeline";
export interface SpeechRequest {
  id: number;
  type: "load" | "transcribe";
  audio?: Float32Array;
}
export interface SpeechResponse {
  id: number;
  type: "ready" | "result" | "progress" | "error";
  text?: string;
  words?: TranscriptWord[];
  progress?: number;
  message?: string;
}
export interface CaptureCallbacks {
  onPitch?: (reading: import("./pitch").PitchReading | undefined) => void;
  onAudio?: (audio: Float32Array) => void;
  onChunk: (audio: Float32Array) => void;
  onLevel?: (level: number) => void;
  onInterrupted: (message: string) => void;
}

export interface ProvisionalSpeech {
  id: string;
  entryId: string;
  text: string;
}
export interface PendingSpeech {
  id: string;
  result: Promise<RecognizedSpeech>;
}

export interface RecognizedSpeech {
  text: string;
  command?: Command;
}

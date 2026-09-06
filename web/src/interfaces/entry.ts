import type { SelectionScale } from "../enums/selection";
import type { AudioSpan } from "./timeline";
export interface TextSelection {
  start: number;
  end: number;
}
export interface TextSnapshot {
  selectionScale?: SelectionScale;
  commits?: TextSelection[];
  text: string;
  selection: TextSelection;
  spans: AudioSpan[];
  lastCommit?: TextSelection;
}
export interface Entry extends TextSnapshot {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  history: TextSnapshot[];
  future: TextSnapshot[];
  clipIds: string[];
}
export interface AudioClip {
  recordingId?: string;
  recordingOffset?: number;
  id: string;
  entryId: string;
  createdAt: string;
  audio: Blob;
  duration: number;
  transcript: string;
  transcribed: boolean;
}

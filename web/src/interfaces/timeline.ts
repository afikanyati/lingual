import type { TextSelection } from "./entry";
export interface AudioSpan extends TextSelection {
  clipId: string;
  recordingId?: string;
  recordedStart?: number;
  recordedEnd?: number;
  ordinal?: number;
  sourceStart: number;
  sourceEnd: number;
  rate: number;
  gain: number;
  emphasized?: boolean;
  pitch?: number;
  power?: number;
  speakingRate?: number;
}
export interface TranscriptWord {
  text: string;
  start: number;
  end: number;
}
export interface Transcript {
  text: string;
  words: TranscriptWord[];
}
export interface Passage {
  text: string;
  spans: AudioSpan[];
}
export interface PlaybackSlice {
  omitSilences?: boolean;
  clipId: string;
  start: number;
  end: number;
  rate: number;
  gain: number;
  textStart: number;
  textEnd: number;
}

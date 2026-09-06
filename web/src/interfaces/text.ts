import type { TextSelection } from "./entry";

/** A displayed fragment retains the exact range of the immutable transcript it represents. */
export interface TextFragment extends TextSelection {
  text: string;
}

/** Cursor position is in the original transcript, even when Echo expands punctuation names. */
export interface EchoCursor {
  range: TextSelection;
  position: number;
}

/** Character boundaries map a punctuation-free view back to the untouched transcript. */
export interface TextPresentation {
  text: string;
  sourceStarts: number[];
  sourceEnds: number[];
  sourceLength: number;
}

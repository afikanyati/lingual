import type { Entry, AudioClip } from "./entry";
export interface EncodedClip extends Omit<AudioClip, "audio"> {
  mimeType: string;
  base64: string;
}
export interface LingualBackup {
  format: "lingual-web";
  version: 1;
  entries: Entry[];
  clips: EncodedClip[];
}

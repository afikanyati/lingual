import type { AudioClip, Entry } from "./entry";
export interface WelcomeClip extends Omit<AudioClip, "audio"> {
  file: string;
}
export interface WelcomeManifest {
  entry: Entry;
  clips: WelcomeClip[];
}

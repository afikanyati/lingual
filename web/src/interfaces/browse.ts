export interface BrowseClockOptions {
  mode: "walk" | "run";
  headphonesConnected: boolean;
  rate: number;
  duration: number;
  play: () => Promise<void>;
  echo: () => void;
  next: () => void;
  onError?: (cause: unknown) => void;
}

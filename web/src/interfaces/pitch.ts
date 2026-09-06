/** A voiced measurement has a frequency/note; unvoiced frames explicitly clear the readout. */
export interface PitchReading {
  frequency?: number;
  note: string;
  power: number;
  time: number;
}

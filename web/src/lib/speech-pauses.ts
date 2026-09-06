export interface SpeechInterval {
  start: number;
  end: number;
}

/** Locate audible regions within a word estimate. Preserve short phonetic gaps and 30 ms of edge audio. */
export function speechIntervals(
  audio: Float32Array,
  start: number,
  end: number,
  sampleRate = 16000,
): SpeechInterval[] {
  const first = Math.max(0, Math.floor(start * sampleRate));
  const last = Math.min(audio.length, Math.ceil(end * sampleRate));
  const frame = Math.round(sampleRate * 0.01);
  const energies: number[] = [];
  for (let offset = first; offset < last; offset += frame) {
    const stop = Math.min(last, offset + frame);
    let energy = 0;
    for (let index = offset; index < stop; index++) energy += audio[index] ** 2;
    energies.push(Math.sqrt(energy / (stop - offset)));
  }
  const peak = energies.reduce(
    (maximum, energy) => Math.max(maximum, energy),
    0,
  );
  // A relative threshold keeps quiet recordings audible; never erase a word on uncertain evidence.
  if (peak < 0.0001) return [{ start, end }];
  const threshold = Math.max(0.0001, peak * 0.025);
  const voiced = energies.flatMap((energy, index) =>
    energy >= threshold ? [index] : [],
  );
  const groups: { first: number; last: number }[] = [];
  for (const index of voiced) {
    const previous = groups.at(-1);
    if (previous && index - previous.last <= 10) previous.last = index;
    else groups.push({ first: index, last: index });
  }
  return groups.map((group) => ({
    start: Math.max(start, (first + group.first * frame) / sampleRate - 0.03),
    end: Math.min(end, (first + (group.last + 1) * frame) / sampleRate + 0.03),
  }));
}

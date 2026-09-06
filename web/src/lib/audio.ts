/** Join every captured sample, including the final incomplete recording chunk. */
export function joinSamples(chunks: Float32Array[]): Float32Array {
  const output = new Float32Array(
    chunks.reduce((sum, chunk) => sum + chunk.length, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}
export function hasSpeechEnergy(samples: Float32Array): boolean {
  if (!samples.length) return false;
  const energy =
    samples.reduce((sum, value) => sum + value * value, 0) / samples.length;
  return Math.sqrt(energy) > 0.001;
}
/** Encode locally so recorded speech can be exported or retried without a transcription service. */
export function encodeWav(samples: Float32Array, sampleRate = 16000): Blob {
  const data = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(data);
  const write = (offset: number, text: string) =>
    [...text].forEach((char, index) =>
      view.setUint8(offset + index, char.charCodeAt(0)),
    );
  write(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  write(8, "WAVE");
  write(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  write(36, "data");
  view.setUint32(40, samples.length * 2, true);
  samples.forEach((sample, index) =>
    view.setInt16(
      44 + index * 2,
      Math.max(-1, Math.min(1, sample)) * (sample < 0 ? 32768 : 32767),
      true,
    ),
  );
  return new Blob([data], { type: "audio/wav" });
}
export async function decodeAudio(blob: Blob): Promise<Float32Array> {
  const context = new AudioContext();
  try {
    const source = await context.decodeAudioData(await blob.arrayBuffer());
    const offline = new OfflineAudioContext(
      1,
      Math.ceil(source.duration * 16000),
      16000,
    );
    const node = offline.createBufferSource();
    node.buffer = source;
    node.connect(offline.destination);
    node.start();
    return (await offline.startRendering()).getChannelData(0);
  } finally {
    await context.close();
  }
}
export function downloadBlob(blob: Blob, name: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = name;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function formatTime(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
}

import type { LingualBackup, EncodedClip } from "../interfaces/backup";
import type {
  AudioClip,
  Entry,
  TextSnapshot,
  TextSelection,
} from "../interfaces/entry";
import { SelectionScale } from "../enums/selection";
import { hasCompleteAudio } from "./audio-integrity";
import { loadEntries, loadClips, importRecords } from "./storage";

/** JSON is untrusted: optional metadata needs the same checks as required fields. */
function validRange(value: unknown, length: number): boolean {
  if (!value || typeof value !== "object") return false;
  const range = value as TextSelection;
  return (
    Number.isInteger(range.start) &&
    Number.isInteger(range.end) &&
    range.start >= 0 &&
    range.end >= range.start &&
    range.end <= length
  );
}
function validDate(value: unknown): boolean {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}
function optionalNumber(value: unknown, minimum = -Infinity): boolean {
  return (
    value === undefined ||
    (typeof value === "number" && Number.isFinite(value) && value >= minimum)
  );
}
function optionalString(value: unknown): boolean {
  return value === undefined || typeof value === "string";
}

function validSnapshot(value: unknown): value is TextSnapshot {
  if (!value || typeof value !== "object") return false;
  const item = value as TextSnapshot;
  return (
    typeof item.text === "string" &&
    validRange(item.selection, item.text.length) &&
    (item.lastCommit === undefined ||
      validRange(item.lastCommit, item.text.length)) &&
    (item.commits === undefined ||
      (Array.isArray(item.commits) &&
        item.commits.every((range) => validRange(range, item.text.length)))) &&
    (item.selectionScale === undefined ||
      Object.values(SelectionScale).includes(item.selectionScale)) &&
    Array.isArray(item.spans) &&
    item.spans.every(
      (span) =>
        span !== null &&
        typeof span === "object" &&
        optionalString(span.recordingId) &&
        optionalNumber(span.recordedStart, 0) &&
        optionalNumber(span.recordedEnd, 0) &&
        optionalNumber(span.ordinal, 0) &&
        optionalNumber(span.pitch, 0) &&
        optionalNumber(span.power) &&
        optionalNumber(span.speakingRate, 0) &&
        (span.emphasized === undefined ||
          typeof span.emphasized === "boolean") &&
        typeof span.clipId === "string" &&
        Number.isFinite(span.start) &&
        Number.isFinite(span.end) &&
        span.start >= 0 &&
        span.end <= item.text.length &&
        span.end > span.start &&
        Number.isFinite(span.sourceStart) &&
        Number.isFinite(span.sourceEnd) &&
        span.sourceStart >= 0 &&
        span.sourceEnd > span.sourceStart &&
        Number.isFinite(span.rate) &&
        span.rate >= 0.2 &&
        span.rate <= 3 &&
        Number.isFinite(span.gain) &&
        span.gain >= 0 &&
        span.gain <= 1,
    )
  );
}
/** Validate the entire archive before writing, so a partial or foreign file cannot corrupt saved entries. */
export function validateBackup(value: unknown): LingualBackup {
  const data = value as LingualBackup | undefined;
  if (
    !data ||
    data.format !== "lingual-web" ||
    data.version !== 1 ||
    !Array.isArray(data.entries) ||
    !Array.isArray(data.clips)
  )
    throw new Error("This is not a supported Lingual web backup.");
  for (const entry of data.entries) {
    if (
      !validSnapshot(entry) ||
      typeof entry.id !== "string" ||
      typeof entry.title !== "string" ||
      !validDate(entry.createdAt) ||
      !validDate(entry.updatedAt) ||
      !Array.isArray(entry.history) ||
      !entry.history.every(validSnapshot) ||
      !Array.isArray(entry.future) ||
      !entry.future.every(validSnapshot) ||
      !Array.isArray(entry.clipIds) ||
      !entry.clipIds.every((id) => typeof id === "string")
    )
      throw new Error("An entry in this backup is malformed.");
  }
  for (const clip of data.clips) {
    if (
      !clip ||
      typeof clip.id !== "string" ||
      typeof clip.entryId !== "string" ||
      !optionalString(clip.recordingId) ||
      !optionalNumber(clip.recordingOffset, 0) ||
      !Number.isFinite(clip.duration) ||
      clip.duration < 0 ||
      typeof clip.mimeType !== "string" ||
      !clip.mimeType.startsWith("audio/") ||
      typeof clip.base64 !== "string" ||
      !/^[A-Za-z0-9+/]*={0,2}$/.test(clip.base64) ||
      clip.base64.length % 4 !== 0 ||
      typeof clip.transcript !== "string" ||
      typeof clip.transcribed !== "boolean" ||
      !validDate(clip.createdAt)
    )
      throw new Error("A recording in this backup is malformed.");
  }
  if (
    new Set(data.entries.map((entry) => entry.id)).size !==
      data.entries.length ||
    new Set(data.clips.map((clip) => clip.id)).size !== data.clips.length
  )
    throw new Error("This backup contains duplicate identifiers.");
  const clipIds = new Set(data.clips.map((clip) => clip.id));
  for (const entry of data.entries) {
    if (![entry, ...entry.history, ...entry.future].every(hasCompleteAudio))
      throw new Error(
        "This backup contains words without their original recording. Keep the archive for recovery; entries in Lingual must come from speech.",
      );
    if (
      [
        ...entry.clipIds,
        ...[entry, ...entry.history, ...entry.future].flatMap((snapshot) =>
          snapshot.spans.map((span) => span.clipId),
        ),
      ].some((id) => !clipIds.has(id))
    )
      throw new Error("This backup is missing a referenced recording.");
  }
  return data;
}
export async function exportBackup(): Promise<Blob> {
  const entries = await loadEntries();
  const clips = new Map<string, AudioClip>();
  for (const entry of entries)
    for (const clip of await loadClips(entry.id)) clips.set(clip.id, clip);
  const encoded: EncodedClip[] = [];
  for (const clip of clips.values()) {
    const bytes = new Uint8Array(await clip.audio.arrayBuffer());
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 32768)
      binary += String.fromCharCode(...bytes.subarray(offset, offset + 32768));
    const { audio: _audio, ...metadata } = clip;
    encoded.push({
      ...metadata,
      mimeType: clip.audio.type,
      base64: btoa(binary),
    });
  }
  return new Blob(
    [
      JSON.stringify({
        format: "lingual-web",
        version: 1,
        entries,
        clips: encoded,
      } satisfies LingualBackup),
    ],
    { type: "application/json" },
  );
}
/** Remap identifiers on restore: importing a backup always adds entries and never overwrites current work. */
export async function importBackup(value: unknown): Promise<void> {
  const data = validateBackup(value);
  const entryIds = new Map(
    data.entries.map((entry) => [entry.id, crypto.randomUUID()]),
  );
  const clipIds = new Map(
    data.clips.map((clip) => [clip.id, crypto.randomUUID()]),
  );
  const remapSnapshot = (snapshot: TextSnapshot): TextSnapshot => ({
    ...snapshot,
    spans: snapshot.spans.map((span) => ({
      ...span,
      clipId: clipIds.get(span.clipId)!,
    })),
  });
  const entries: Entry[] = data.entries.map((entry) => ({
    ...entry,
    ...remapSnapshot(entry),
    id: entryIds.get(entry.id)!,
    history: entry.history.map(remapSnapshot),
    future: entry.future.map(remapSnapshot),
    clipIds: entry.clipIds.map((id) => clipIds.get(id)!),
  }));
  const clips: AudioClip[] = data.clips.map((clip) => ({
    id: clipIds.get(clip.id)!,
    recordingId: clip.recordingId,
    recordingOffset: clip.recordingOffset,
    entryId:
      entryIds.get(clip.entryId) ??
      entries.find((entry) => entry.clipIds.includes(clipIds.get(clip.id)!))
        ?.id ??
      "",
    createdAt: clip.createdAt,
    transcript: clip.transcript,
    transcribed: clip.transcribed,
    duration: clip.duration,
    audio: new Blob(
      [Uint8Array.from(atob(clip.base64), (char) => char.charCodeAt(0))],
      { type: clip.mimeType },
    ),
  }));
  await importRecords(entries, clips);
}

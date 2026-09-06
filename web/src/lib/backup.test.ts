import "fake-indexeddb/auto";
import { describe, it, expect } from "vitest";
import { validateBackup, exportBackup, importBackup } from "./backup";
import { createEntry, undo } from "./editor";
import { insertPassage } from "./timeline";
import { spokenPassage } from "../test/fixtures";
import { encodeWav } from "./audio";
import { saveEntry, saveClip, loadEntries, loadClip } from "./storage";
describe("portable entry backups", () => {
  it("rejects unsupported formats and malformed records without touching storage", () => {
    expect(() =>
      validateBackup({ version: 999, entries: [], clips: [] }),
    ).toThrow();
    expect(() =>
      validateBackup({
        format: "lingual-web",
        version: 1,
        entries: [{ id: "x", text: 123 }],
        clips: [],
      }),
    ).toThrow();
  });
  it("accepts a valid empty entry archive", () => {
    expect(
      validateBackup({
        format: "lingual-web",
        version: 1,
        entries: [createEntry()],
        clips: [],
      }).entries,
    ).toHaveLength(1);
  });
  it("rejects dangling audio references", () => {
    const entry = { ...createEntry(), clipIds: ["missing"] };
    expect(() =>
      validateBackup({
        format: "lingual-web",
        version: 1,
        entries: [entry],
        clips: [],
      }),
    ).toThrow(/recording/);
  });
});

for (const location of ["entry", "history", "future"] as const) {
  it(`rejects unrecorded words in backup ${location}`, () => {
    const entry = createEntry();
    const unrecorded = {
      text: "unrecorded words",
      selection: { start: 0, end: 0 },
      spans: [],
    };
    if (location === "entry") Object.assign(entry, unrecorded);
    else entry[location] = [unrecorded];
    expect(() =>
      validateBackup({
        format: "lingual-web",
        version: 1,
        entries: [entry],
        clips: [],
      }),
    ).toThrow(/recording/);
  });
}

it("restores recorded entries and their history with new identifiers and identical audio bytes", async () => {
  let entry = insertPassage(
    createEntry(),
    spokenPassage("one two", "recorded"),
  );
  entry = undo(insertPassage(entry, spokenPassage("three", "recorded")));
  const audio = encodeWav(new Float32Array(32000).fill(0.1));
  await saveEntry(entry);
  await saveClip({
    id: "recorded",
    entryId: entry.id,
    audio,
    duration: 2,
    transcript: "one two three",
    transcribed: true,
    createdAt: entry.createdAt,
  });
  const archive = validateBackup(
    JSON.parse(await (await exportBackup()).text()),
  );
  await importBackup(archive);
  const entries = await loadEntries();
  expect(entries.find((item) => item.id === entry.id)).toEqual(entry);
  const restored = entries.find((item) => item.id !== entry.id)!;
  expect(restored.text).toBe(entry.text);
  expect(restored.history).toHaveLength(entry.history.length);
  expect(restored.future[0].text).toBe("one two three");
  const restoredClipId = restored.spans[0].clipId;
  expect(restoredClipId).not.toBe("recorded");
  expect(
    restored.future[0].spans.every((span) => span.clipId === restoredClipId),
  ).toBe(true);
  expect(await (await loadClip(restoredClipId))!.audio.arrayBuffer()).toEqual(
    await audio.arrayBuffer(),
  );
});

it("keeps measured pitch attached to the recorded word through copy, edit history, persistence and backup restore", async () => {
  const phrase = spokenPassage("pitched word", "pitch-recording");
  phrase.spans[0].pitch = 220;
  phrase.spans[1].pitch = 440;
  const initial = insertPassage(createEntry(), phrase);
  const { copyPassage } = await import("./timeline");
  const { replaceRange, redo } = await import("./editor");
  const edited = replaceRange(initial, 0, 8, "");
  expect(edited.spans[0].pitch).toBe(440);
  expect(undo(edited).spans.map((span) => span.pitch)).toEqual([220, 440]);
  expect(redo(undo(edited)).spans[0].pitch).toBe(440);
  expect(copyPassage(initial, { start: 0, end: 7 }).spans[0].pitch).toBe(220);
  await saveEntry(edited);
  await saveClip({
    id: "pitch-recording",
    entryId: initial.id,
    createdAt: initial.createdAt,
    duration: 2,
    audio: encodeWav(new Float32Array(32000)),
    transcript: phrase.text,
    transcribed: true,
  });
  const archive = validateBackup(
    JSON.parse(await (await exportBackup()).text()),
  );
  await importBackup({
    ...archive,
    entries: archive.entries.filter((entry) => entry.id === initial.id),
    clips: archive.clips.filter((clip) => clip.id === "pitch-recording"),
  });
  const restored = (await loadEntries()).find(
    (entry) => entry.id !== initial.id && entry.text === edited.text,
  )!;
  expect(restored.spans[0].pitch).toBe(440);
  expect(undo(restored).spans.map((span) => span.pitch)).toEqual([220, 440]);
});

// Untrusted archives must not persist metadata that later crashes editing or playback.
for (const metadata of [
  { commits: "not an array" },
  { commits: [null] },
  { lastCommit: { start: -1, end: 4 } },
  { selectionScale: "unexpected" },
  { createdAt: 2000 },
  { updatedAt: 2000 },
  { spans: [null] },
]) {
  it(`rejects malformed optional editing metadata ${JSON.stringify(metadata)}`, async () => {
    const before = await loadEntries();
    await expect(
      importBackup({
        format: "lingual-web",
        version: 1,
        entries: [{ ...createEntry(), ...metadata }],
        clips: [],
      }),
    ).rejects.toThrow(/malformed/);
    expect(await loadEntries()).toEqual(before);
  });
}

it("rejects malformed optional recording metadata before saving", () => {
  const entry = createEntry();
  expect(() =>
    validateBackup({
      format: "lingual-web",
      version: 1,
      entries: [entry],
      clips: [
        {
          id: "bad",
          entryId: entry.id,
          createdAt: entry.createdAt,
          duration: 1,
          mimeType: "audio/wav",
          base64: "AAAA",
          transcript: "",
          transcribed: true,
          recordingOffset: -100,
        },
      ],
    }),
  ).toThrow(/malformed/);
});

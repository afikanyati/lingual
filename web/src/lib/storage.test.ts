import "fake-indexeddb/auto";
import { describe, it, expect } from "vitest";
import { createEntry } from "./editor";
import {
  loadEntries,
  saveEntry,
  saveClip,
  loadClips,
  deleteEntry,
} from "./storage";

describe("local persistence", () => {
  it("restores entry history and its original audio then removes both atomically", async () => {
    const entry = createEntry();
    await saveEntry(entry);
    await saveClip({
      id: "clip-1",
      entryId: entry.id,
      audio: new Blob(["audio"]),
      duration: 1,
      createdAt: new Date().toISOString(),
      transcript: "",
      transcribed: false,
    });
    expect((await loadEntries()).find((item) => item.id === entry.id)).toEqual(
      entry,
    );
    expect(await loadClips(entry.id)).toHaveLength(1);
    await deleteEntry(entry.id);
    expect(
      (await loadEntries()).find((item) => item.id === entry.id),
    ).toBeUndefined();
    expect(await loadClips(entry.id)).toHaveLength(0);
  });
});

it("retains copied audio after deleting its source entry, including an unpasted clipboard", async () => {
  const first = createEntry();
  const second = { ...createEntry(), clipIds: ["shared-audio"] };
  await saveEntry(first);
  await saveEntry(second);
  await saveClip({
    id: "shared-audio",
    entryId: first.id,
    audio: new Blob(["audio"]),
    duration: 1,
    createdAt: first.createdAt,
    transcript: "",
    transcribed: false,
  });
  await saveClip({
    id: "clipboard-only",
    entryId: first.id,
    audio: new Blob(["audio"]),
    duration: 1,
    createdAt: first.createdAt,
    transcript: "",
    transcribed: false,
  });
  await deleteEntry(first.id, ["clipboard-only"]);
  expect((await loadClips(second.id)).map((clip) => clip.id)).toContain(
    "shared-audio",
  );
  const third = { ...createEntry(), clipIds: ["clipboard-only"] };
  await saveEntry(third);
  expect((await loadClips(third.id)).map((clip) => clip.id)).toContain(
    "clipboard-only",
  );
});

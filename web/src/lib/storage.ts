import { openDB } from "idb";
import type { Entry, AudioClip } from "../interfaces/entry";

const database = () =>
  openDB("lingual-local", 1, {
    upgrade(db) {
      db.createObjectStore("entries", { keyPath: "id" });
      db.createObjectStore("clips", { keyPath: "id" });
    },
  });
export async function loadEntries(): Promise<Entry[]> {
  const db = await database();
  return (await db.getAll("entries"))
    .map((entry: Entry) => ({
      ...entry,
      spans: entry.spans ?? [],
      history: entry.history.map((item) => ({
        ...item,
        spans: item.spans ?? [],
      })),
      future: entry.future.map((item) => ({
        ...item,
        spans: item.spans ?? [],
      })),
    }))
    .sort((a: Entry, b: Entry) => b.updatedAt.localeCompare(a.updatedAt));
}
export async function saveEntry(entry: Entry): Promise<void> {
  const db = await database();
  await db.put("entries", entry);
}
export async function loadClips(entryId: string): Promise<AudioClip[]> {
  const db = await database();
  const entry: Entry | undefined = await db.get("entries", entryId);
  return (await db.getAll("clips"))
    .filter(
      (clip: AudioClip) =>
        clip.entryId === entryId || entry?.clipIds.includes(clip.id),
    )
    .sort((a: AudioClip, b: AudioClip) =>
      a.createdAt.localeCompare(b.createdAt),
    );
}
export async function saveClip(clip: AudioClip): Promise<void> {
  const db = await database();
  await db.put("clips", clip);
}
/** Remove the entry and its audio in one transaction, preventing orphaned recordings. */
export async function deleteEntry(
  id: string,
  retainedClipIds: string[] = [],
): Promise<void> {
  const db = await database();
  const tx = db.transaction(["entries", "clips"], "readwrite");
  await tx.objectStore("entries").delete(id);
  const remaining: Entry[] = await tx.objectStore("entries").getAll();
  let cursor = await tx.objectStore("clips").openCursor();
  while (cursor) {
    if (
      cursor.value.entryId === id &&
      !retainedClipIds.includes(cursor.value.id) &&
      !remaining.some((entry) => entry.clipIds.includes(cursor!.value.id))
    )
      await cursor.delete();
    cursor = await cursor.continue();
  }
  await tx.done;
}

export async function loadClip(id: string): Promise<AudioClip | undefined> {
  const db = await database();
  return db.get("clips", id);
}

export async function importRecords(
  entries: Entry[],
  clips: AudioClip[],
): Promise<void> {
  const db = await database();
  const tx = db.transaction(["entries", "clips"], "readwrite");
  for (const clip of clips) await tx.objectStore("clips").put(clip);
  for (const entry of entries) await tx.objectStore("entries").put(entry);
  await tx.done;
}

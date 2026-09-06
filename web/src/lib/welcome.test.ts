import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, afterEach, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { openWelcome } from "./welcome";
import { loadEntries, loadClips } from "./storage";
import { hasCompleteAudio } from "./audio-integrity";
import { entryPresentation } from "./prosody";
import { defaultPreferences } from "./commands";
import type { WelcomeManifest } from "../interfaces/welcome";
beforeEach(() => vi.stubGlobal("indexedDB", new IDBFactory()));
afterEach(() => vi.unstubAllGlobals());
it("presents a real thousand-word entry without blocking the interface for seconds", () => {
  const { entry }: WelcomeManifest = JSON.parse(
    readFileSync("public/welcome/manifest.json", "utf8"),
  );
  const started = performance.now();
  const first = entryPresentation(entry, defaultPreferences);
  expect(entryPresentation(entry, defaultPreferences)).toEqual(first);
  expect(first.text).toContain("First things first");
  expect(performance.now() - started).toBeLessThan(1500);
});
it("imports the original welcome words, pitch and both recordings once, with complete audio links", async () => {
  const fetcher = vi.fn(
    async (url: string) =>
      new Response(readFileSync(`public/${url.replace(/^\//, "")}`)),
  );
  vi.stubGlobal("fetch", fetcher);
  const id = await openWelcome();
  const entries = await loadEntries();
  expect(entries).toHaveLength(1);
  expect(entries[0].title).toBe("Welcome to Lingual");
  expect(entries[0].spans).toHaveLength(996);
  expect(entries[0].spans.some((span) => span.pitch)).toBe(true);
  expect(hasCompleteAudio(entries[0])).toBe(true);
  expect(await loadClips(id)).toHaveLength(2);
  expect(await openWelcome()).toBe(id);
  expect(fetcher).toHaveBeenCalledTimes(3);
});
it("does not leave a text-only welcome entry when one recording fails to download", async () => {
  vi.stubGlobal("fetch", async (url: string) =>
    url.endsWith("manifest.json")
      ? new Response(readFileSync("public/welcome/manifest.json"))
      : new Response("failed", { status: 503 }),
  );
  await expect(openWelcome()).rejects.toThrow(/welcome recording/i);
  expect(await loadEntries()).toHaveLength(0);
});

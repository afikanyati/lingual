import { test, expect } from "@playwright/test";
import { installSpeechHardware, record, select } from "./hardware";

test("all native actions are discoverable, with selection update and persisted settings", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  const editor = page.getByRole("textbox", { name: "Entry text" });
  await record(page, "One small thought. Another sentence.");
  await select(page, 35, 35);
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("SELECT_SENTENCE");
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("UPDATE_SELECTION");
  await record(page, "A new thought.", true);
  await expect(editor).toHaveValue("One small thought. Another sentence.");
  await page.getByRole("button", { name: "Accept replacement" }).click();
  await expect(editor).toHaveValue("One small thought. A new thought.");
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(editor).toHaveValue("One small thought. Another sentence.");
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await expect(page.locator(".command-palette button")).toHaveCount(92);
  await page.getByLabel("Find a voice action").fill("volume");
  await expect(page.locator(".command-palette button")).toHaveCount(2);
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page
    .getByRole("button", { name: "Settings", exact: true })
    .first()
    .click();
  await page.getByLabel("Playback speed").selectOption("1.5");
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page.reload();
  await page
    .getByRole("button", { name: "Settings", exact: true })
    .first()
    .click();
  await expect(page.getByLabel("Playback speed")).toHaveValue("1.5");
});

test("audio-linked selections preserve a cross-entry clipboard and export edited audio", async ({
  page,
}) => {
  await page.goto("/");
  await page.waitForFunction(() =>
    document.querySelector(".new-entry:not(:disabled)"),
  );
  // Real IndexedDB and WAV data exercise persistence, rendering and browser audio without a model download.
  await page.evaluate(async () => {
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const request = indexedDB.open("lingual-local", 1);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const entries = await new Promise<any[]>((resolve) => {
      const request = db.transaction("entries").objectStore("entries").getAll();
      request.onsuccess = () => resolve(request.result);
    });
    const entry = entries[0];
    const samples = new Float32Array(16000);
    samples.forEach(
      (_, i) => (samples[i] = 0.1 * Math.sin((2 * Math.PI * 220 * i) / 16000)),
    );
    const wav = new ArrayBuffer(44 + samples.length * 2);
    const view = new DataView(wav);
    const write = (offset: number, text: string) =>
      [...text].forEach((char, i) =>
        view.setUint8(offset + i, char.charCodeAt(0)),
      );
    write(0, "RIFF");
    view.setUint32(4, wav.byteLength - 8, true);
    write(8, "WAVE");
    write(12, "fmt ");
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, 1, true);
    view.setUint32(24, 16000, true);
    view.setUint32(28, 32000, true);
    view.setUint16(32, 2, true);
    view.setUint16(34, 16, true);
    write(36, "data");
    view.setUint32(40, samples.length * 2, true);
    samples.forEach((sample, i) =>
      view.setInt16(44 + i * 2, sample * 32767, true),
    );
    entry.text = "one two";
    entry.spans = [
      {
        start: 0,
        end: 3,
        clipId: "fixture",
        sourceStart: 0,
        sourceEnd: 0.3,
        rate: 1,
        gain: 1,
        ordinal: 0,
      },
      {
        start: 4,
        end: 7,
        clipId: "fixture",
        sourceStart: 0.5,
        sourceEnd: 0.8,
        rate: 1,
        gain: 1,
        ordinal: 1,
      },
    ];
    entry.clipIds = ["fixture"];
    entry.history = [];
    entry.future = [];
    const tx = db.transaction(["entries", "clips"], "readwrite");
    tx.objectStore("entries").put(entry);
    tx.objectStore("clips").put({
      id: "fixture",
      entryId: entry.id,
      createdAt: entry.createdAt,
      audio: new Blob([wav], { type: "audio/wav" }),
      duration: 1,
      transcript: "one two",
      transcribed: true,
    });
    await new Promise((resolve) => (tx.oncomplete = resolve));
    db.close();
  });
  await page.reload();
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await page.getByRole("button", { name: "two", exact: true }).click();
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("COPY_SELECTION");
  await page.getByRole("button", { name: "New entry" }).click();
  await page.getByRole("button", { name: "Paste Lingual clipboard" }).click();
  await expect(
    page.getByRole("button", { name: "two", exact: true }),
  ).toHaveAttribute("data-tooltip", /0.50–0.80s/);
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.locator(".playback-controls")).toBeVisible();
  // An ordinary click now seeks in playing audio, as in native Lingual. Shift-click explicitly selects it.
  await page
    .getByRole("button", { name: "two", exact: true })
    .click({ modifiers: ["Shift"] });
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("EXPORT_SELECTION");
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export audio", exact: true }).click();
  expect((await download).suggestedFilename()).toMatch(/\.wav$/);
});

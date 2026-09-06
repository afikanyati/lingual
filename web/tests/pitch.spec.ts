import { test, expect } from "@playwright/test";
import { installSpeechHardware } from "./hardware";

test("the microphone drives live musical notes and clears pitch during silence and after Stop", async ({
  page,
}, testInfo) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  const pitch = page.getByRole("status", { name: "Pitch", exact: true });
  await expect(pitch).toContainText("—");
  const signal = async (frequency: number) =>
    page.evaluate((hz) => {
      const samples = Float32Array.from({ length: 4096 }, (_, index) =>
        hz ? 0.15 * Math.sin((2 * Math.PI * hz * index) / 16000) : 0,
      );
      (window as any).lingualHardware.process({
        inputBuffer: { getChannelData: () => samples },
      });
    }, frequency);
  await signal(220);
  await expect(pitch).toContainText("A3");
  await expect(pitch).toContainText("220 Hz");
  await page.screenshot({
    path: testInfo.outputPath("live-pitch.png"),
    fullPage: true,
  });
  await signal(440);
  await expect(pitch).toContainText("A4");
  await signal(0);
  await expect(pitch).toContainText("—");
  await expect(pitch).not.toContainText("Hz");
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Resume entry", exact: true }),
  ).toBeEnabled();
  await expect(pitch).toHaveCount(0);
});

test("saved word pitch follows playback, survives pause, and clears on an unvoiced word and Stop", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await expect(page.locator(".new-entry")).toBeEnabled();
  await page.evaluate(async () => {
    const request = indexedDB.open("lingual-local", 1);
    const db = await new Promise<IDBDatabase>(
      (resolve) => (request.onsuccess = () => resolve(request.result)),
    );
    const read = db.transaction("entries").objectStore("entries").getAll();
    const entries = await new Promise<any[]>(
      (resolve) => (read.onsuccess = () => resolve(read.result)),
    );
    const entry = entries[0];
    entry.text = "lower higher unvoiced";
    entry.spans = [
      { start: 0, end: 5, pitch: 220 },
      { start: 6, end: 12, pitch: 440 },
      { start: 13, end: 21 },
    ].map((span, index) => ({
      ...span,
      clipId: "pitch",
      ordinal: index,
      sourceStart: index,
      sourceEnd: index + 1,
      rate: 1,
      gain: 1,
    }));
    entry.clipIds = ["pitch"];
    entry.history = [];
    entry.future = [];
    entry.selection = { start: 0, end: 0 };
    const wav = new ArrayBuffer(44 + 48000 * 2);
    const view = new DataView(wav);
    const write = (offset: number, text: string) =>
      [...text].forEach((char, index) =>
        view.setUint8(offset + index, char.charCodeAt(0)),
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
    view.setUint32(40, 96000, true);
    for (let i = 0; i < 48000; i++)
      view.setInt16(
        44 + i * 2,
        4000 * Math.sin((2 * Math.PI * 220 * i) / 16000),
        true,
      );
    const tx = db.transaction(["entries", "clips"], "readwrite");
    tx.objectStore("entries").put(entry);
    tx.objectStore("clips").put({
      id: "pitch",
      entryId: entry.id,
      createdAt: entry.createdAt,
      audio: new Blob([wav], { type: "audio/wav" }),
      duration: 3,
      transcript: entry.text,
      transcribed: true,
    });
    await new Promise((resolve) => (tx.oncomplete = resolve));
    db.close();
  });
  await page.reload();
  await page
    .getByRole("button", { name: "Audio-linked view", exact: true })
    .click();
  await page.getByRole("button", { name: "lower", exact: true }).click();
  await expect(
    page.locator(".playback-controls").getByRole("button", { name: /Resume/ }),
  ).toBeVisible();
  await expect(
    page.getByRole("status", { name: "Pitch", exact: true }),
  ).toContainText("A3");
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Play", exact: true }).click();
  const pitch = page.getByRole("status", { name: "Pitch", exact: true });
  await expect(pitch).toContainText("A3");
  await page
    .locator(".playback-controls")
    .getByRole("button", { name: /Pause/ })
    .click();
  await expect(pitch).toContainText("A3");
  await page
    .locator(".playback-controls")
    .getByRole("button", { name: /Resume/ })
    .click();
  await expect(pitch).toContainText("A4");
  await expect(pitch).toContainText("—");
  await page
    .locator(".playback-controls")
    .getByRole("button", { name: /Stop/ })
    .click();
  // Stop may remove the pitch readout entirely or leave an empty live readout as listening resumes.
  await expect(pitch.filter({ hasText: "Hz" })).toHaveCount(0);
});

import { test, expect, type Page } from "@playwright/test";
import { installSpeechHardware, say, record } from "./hardware";

/** Inspect persisted data, including audio that is not visible in the transcript. */
async function saved(page: Page) {
  return page.evaluate(async () => {
    const db = await new Promise<IDBDatabase>((resolve) => {
      const request = indexedDB.open("lingual-local", 1);
      request.onsuccess = () => resolve(request.result);
    });
    const read = (store: string) =>
      new Promise<any[]>((resolve) => {
        const request = db.transaction(store).objectStore(store).getAll();
        request.onsuccess = () => resolve(request.result);
      });
    const entries = await read("entries");
    const clips = await read("clips");
    db.close();
    return { entries, clips: clips.map(({ audio, ...clip }) => clip) };
  });
}

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
});

test("Enable voice hears speech immediately without saving text or audio to the selected entry", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    page.getByRole("region", { name: "Voice command guide" }),
  ).toHaveCount(0);
  const before = await saved(page);
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  const listening = page.getByRole("region", { name: "Listening only" });
  await expect(listening).toBeVisible();
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("just thinking"),
  );
  await expect(listening.getByLabel("Heard speech")).toHaveText(
    "just thinking",
  );
  await expect(page.getByLabel("Uncommitted speech")).toHaveCount(0);
  await say(page, "just thinking about something");
  await expect(listening.getByLabel("Heard speech")).toHaveText(
    "just thinking about something",
  );
  await expect(page.getByLabel("Entry text")).toHaveValue("");
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await expect(listening).toHaveCount(0);
  expect(await saved(page)).toEqual(before);
  expect(
    await page.evaluate(
      () => (window as any).lingualHardware.whisperReplies.length,
    ),
  ).toBe(0);
  await page
    .getByRole("button", { name: "Start listening", exact: true })
    .click();
  await expect(listening).toBeVisible();
  await page.screenshot({
    path: info.outputPath("listening-only-mobile.png"),
    fullPage: true,
    animations: "disabled",
  });
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(390);
});

test("start entry creates a recording target; stop entry returns to hearing without modifying it", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  const before = await saved(page);
  await say(page, "start entry");
  await expect(
    page.getByRole("button", { name: "Stop entry", exact: true }),
  ).toBeVisible();
  await say(page, "My recorded words");
  await expect(page.getByLabel("Entry text")).toHaveValue("My recorded words");
  await say(page, "stop entry");
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  const recorded = await saved(page);
  expect(recorded.entries).toHaveLength(before.entries.length + 1);
  expect(
    recorded.entries.find((entry) => entry.id === before.entries[0].id),
  ).toEqual(before.entries[0]);
  await say(page, "These words should stay outside");
  await expect(page.getByLabel("Heard speech")).toHaveText(
    "These words should stay outside",
  );
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  expect(await saved(page)).toEqual(recorded);
  await page.reload();
  await expect(page.getByLabel("Entry text")).toHaveValue("My recorded words");
});

test("explicit resume uses the selected entry and disabling voice actions never turns hearing into dictation", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Voice actions on", exact: true })
    .click();
  const before = await saved(page);
  await say(page, "start entry");
  await expect(page.getByLabel("Heard speech")).toHaveText("start entry");
  expect(await saved(page)).toEqual(before);
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, "Deliberately recorded");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "Deliberately recorded",
  );
  await page.getByRole("button", { name: "Stop entry", exact: true }).click();
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  expect((await saved(page)).entries).toHaveLength(before.entries.length);
});

test("starting from an existing entry preserves its text, audio, and history", async ({
  page,
}) => {
  await record(page, "Keep this existing recording");
  const before = await saved(page);
  await page
    .getByRole("button", { name: "Start listening", exact: true })
    .click();
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  await say(page, "Thinking before I begin");
  await expect(page.getByLabel("Heard speech")).toHaveText(
    "Thinking before I begin",
  );
  expect(await saved(page)).toEqual(before);
  await page.getByRole("button", { name: "Start entry", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Stop entry", exact: true }),
  ).toBeVisible();
  await say(page, "A separate recording");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "A separate recording",
  );
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Resume entry", exact: true }),
  ).toBeEnabled();
  const after = await saved(page);
  expect(
    after.entries.find((entry) => entry.id === before.entries[0].id),
  ).toEqual(before.entries[0]);
  for (const clip of before.clips) expect(after.clips).toContainEqual(clip);
});

test("stopping the microphone discards an unfinished command instead of starting an entry", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  const before = await saved(page);
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("start entry"),
  );
  await expect(page.getByLabel("Heard speech")).toHaveText("start entry");
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Start listening", exact: true }),
  ).toBeVisible();
  expect(await saved(page)).toEqual(before);
  await expect(
    page.getByRole("button", { name: "Stop entry", exact: true }),
  ).toHaveCount(0);
});

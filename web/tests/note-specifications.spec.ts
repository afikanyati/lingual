import { test, expect } from "@playwright/test";
import { readFile } from "node:fs/promises";
import {
  installSpeechHardware,
  say,
  select,
  command,
  record,
} from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
});

test("LTS-001 LTS-032 LTS-033 LTS-038 LTS-039 LTS-044 LTS-045 LTS-159 listening saves speech, stops, and resumes after deletion", async ({
  page,
}) => {
  const editor = page.locator('textarea[aria-label="Entry text"]');
  await expect(
    page
      .locator(".editor-sheet")
      .getByRole("button", { name: "Enable voice", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "New entry" })).toBeDisabled();
  await expect(page.locator(".status-light.active")).toHaveCSS(
    "background-color",
    "rgb(211, 25, 0)",
  );
  await expect(page.locator(".recording-time")).toBeVisible();
  await say(page, "one two three");
  await expect(editor).toHaveValue("one two three");
  await expect
    .poll(() => editor.evaluate((e: HTMLTextAreaElement) => e.selectionStart))
    .toBe(13);
  await page.getByRole("button", { name: /Stop listening/i }).click();
  await expect(
    page.getByRole("button", { name: "Resume entry", exact: true }),
  ).toBeEnabled();
  await expect(page.locator(".recording-time")).toHaveCount(0);
  await select(page, 4, 7);
  await expect(
    page.getByRole("button", { name: "Copy selection", exact: true }),
  ).toBeEnabled();
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("DELETE_SELECTION");
  await expect(editor).toHaveValue("one  three");
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  // Use ordinary dictation: "new" is a native command alias when voice actions are enabled.
  await say(page, "violet");
  await expect(editor).toHaveValue("one violet three");
  await page.getByRole("button", { name: /Stop listening/i }).click();
  await expect
    .poll(() =>
      page.evaluate(() => (window as any).lingualHardware.stoppedTracks),
    )
    .toBe(2);
  await page.reload();
  await expect(editor).toHaveValue("one violet three");
});

for (const action of ["COPY_SELECTION", "CUT_SELECTION", "DELETE_SELECTION"])
  test(`LTS-002 LTS-003 LTS-018 LTS-043 LTS-046 LTS-047 ${action} preserves precise cursor selection`, async ({
    page,
  }) => {
    const editor = page.locator('textarea[aria-label="Entry text"]');
    await record(page, "one two three");
    await select(page, 4, 7);
    await page
      .getByLabel("Selection action", { exact: true })
      .selectOption(action);
    await expect(editor).toHaveValue(
      action === "COPY_SELECTION" ? "one two three" : "one  three",
    );
    await expect
      .poll(() =>
        editor.evaluate((e: HTMLTextAreaElement) => [
          e.selectionStart,
          e.selectionEnd,
        ]),
      )
      .toEqual(action === "COPY_SELECTION" ? [4, 7] : [4, 4]);
    if (action !== "COPY_SELECTION") {
      await page.getByRole("button", { name: "Undo", exact: true }).click();
      await expect(editor).toHaveValue("one two three");
    }
  });

for (const action of ["Accept", "Redo", "Cancel"])
  test(`LTS-071 LTS-072 LTS-073 LTS-074 ${action} replacement through controls`, async ({
    page,
  }) => {
    const editor = page.locator('textarea[aria-label="Entry text"]');
    await record(page, "one two three");
    await select(page, 4, 7);
    await page
      .getByLabel("Selection action", { exact: true })
      .selectOption("UPDATE_SELECTION");
    const draft = page.getByRole("textbox", { name: "Replacement text" });
    await record(page, "new words", true);
    await expect(editor).toHaveValue("one two three");
    await page
      .getByRole("button", { name: `${action} replacement`, exact: true })
      .click();
    if (action === "Accept") {
      await expect(editor).toHaveValue("one new words three");
      await page.getByRole("button", { name: "Undo", exact: true }).click();
      await expect(editor).toHaveValue("one two three");
    }
    if (action === "Redo") {
      await expect(draft).toHaveValue("");
      await expect(editor).toHaveValue("one two three");
    }
    if (action === "Cancel") {
      await expect(draft).toHaveCount(0);
      await expect(editor).toHaveValue("one two three");
    }
  });

test("LTS-094 LTS-095 LTS-098 spoken replace/accept/cancel follow the same staged workflow", async ({
  page,
}) => {
  const editor = page.locator('textarea[aria-label="Entry text"]');
  await record(page, "one two three");
  await select(page, 4, 7);
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Voice actions on" }),
  ).toHaveAttribute("aria-pressed", "true");
  await say(page, "replace selection");
  await expect(
    page.getByRole("textbox", { name: "Replacement text" }),
  ).toBeVisible();
  await expect(page.locator(".voice-console")).toContainText(
    "Recording this entry",
  );
  await say(page, "new words");
  await expect(
    page.getByRole("textbox", { name: "Replacement text" }),
  ).toHaveValue("new words");
  await say(page, "accept");
  await expect(editor).toHaveValue("one new words three");
  await select(page, 4, 13);
  await say(page, "replace selection");
  await expect(
    page.getByRole("textbox", { name: "Replacement text" }),
  ).toBeVisible();
  await expect(page.locator(".voice-console")).toContainText(
    "Recording this entry",
  );
  await say(page, "discard this");
  await expect(
    page.getByRole("textbox", { name: "Replacement text" }),
  ).toHaveValue("discard this");
  await say(page, "cancel");
  await expect(
    page.getByRole("textbox", { name: "Replacement text" }),
  ).toHaveCount(0);
  await expect(editor).toHaveValue("one new words three");
  await page.getByRole("button", { name: /Stop listening/i }).click();
});

test("LTS-028 LTS-034 LTS-035 LTS-058 LTS-059 LTS-076 echo boundaries, pause, resume and rate changes", async ({
  page,
}) => {
  const editor = page.locator('textarea[aria-label="Entry text"]');
  await record(page, "one two three");
  await select(page, 4, 7);
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("ECHO_SELECTION");
  await expect(page.getByRole("button", { name: "Pause echo" })).toBeVisible();
  await page.evaluate(() => (window as any).lingualHardware.boundary(0, 3));
  await expect(page.locator(".transcript-word.word-playing")).toHaveText("two");
  await page.getByRole("button", { name: "Pause echo" }).click();
  await expect(page.getByRole("button", { name: "Resume echo" })).toBeVisible();
  expect(
    await page.evaluate(() => (window as any).lingualHardware.paused),
  ).toBe(true);
  await page.getByRole("button", { name: "Resume echo" }).click();
  await page
    .locator(".playback-controls")
    .getByRole("button", { name: "+", exact: true })
    .click();
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as any).lingualHardware.utterances.at(-1).rate,
      ),
    )
    .toBeCloseTo(1.1);
  await page.evaluate(() => (window as any).lingualHardware.finishEcho());
  await expect(page.locator(".transcript-word.word-playing")).toHaveCount(0);
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  expect(
    await editor.evaluate((e: HTMLTextAreaElement) => [
      e.selectionStart,
      e.selectionEnd,
    ]),
  ).toEqual([4, 7]);
});

for (const mode of ["Walk", "Run"])
  test(`LTS-119 LTS-123 LTS-124 LTS-127 LTS-130 LTS-132 ${mode} controls step, pause and exit`, async ({
    page,
  }) => {
    const editor = page.locator('textarea[aria-label="Entry text"]');
    await record(page, "one two three");
    await page.getByRole("button", { name: mode, exact: true }).click();
    await expect(page.locator(".browse-bar")).toContainText(
      `${mode === "Run" ? "Running" : "Walking"} entry · 1`,
    );
    await page
      .locator(".browse-bar")
      .getByRole("button", { name: "Next" })
      .click();
    await expect(page.locator(".browse-bar")).toContainText("· 2");
    await page
      .locator(".browse-bar")
      .getByRole("button", { name: "Previous" })
      .click();
    await expect(page.locator(".browse-bar")).toContainText("· 1");
    await page
      .locator(".browse-bar")
      .getByRole("button", { name: "Pause", exact: true })
      .click();
    await page
      .locator(".browse-bar")
      .getByRole("button", { name: "Exit" })
      .click();
    await expect(page.locator(".browse-bar")).toHaveCount(0);
  });

test("LTS-183 entering a previewed entry exits entry-list walking", async ({
  page,
}) => {
  await record(page, "one two three");
  await command(page, "walk entry list");
  await expect(page.locator(".browse-bar")).toContainText("Walking entries");
  await command(page, "enter entry");
  await expect(page.locator(".browse-bar")).toHaveCount(0);
});

test("LTS-151 text export contains entry content and LTS-152 LTS-153 deletion requires confirmation", async ({
  page,
}) => {
  const editor = page.locator('textarea[aria-label="Entry text"]');
  await record(page, "one two three");
  await select(page, 4, 7);
  const downloading = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export text", exact: true }).click();
  const download = await downloading;
  expect(await readFile((await download.path())!, "utf8")).toBe(
    "one two three",
  );
  await page.getByRole("button", { name: "Entry options" }).click();
  await page.getByRole("button", { name: "Delete entry", exact: true }).click();
  await page.getByRole("button", { name: "Keep entry" }).click();
  await expect(editor).toHaveValue("one two three");
  await page.getByRole("button", { name: "Entry options" }).click();
  await page.getByRole("button", { name: "Delete entry", exact: true }).click();
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "Delete entry", exact: true })
    .click();
  await expect(editor).toHaveValue("");
  await page.reload();
  await expect(editor).toHaveValue("");
});

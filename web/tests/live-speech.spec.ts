import { test, expect } from "@playwright/test";
import { installSpeechHardware, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
});

test("gray hypotheses appear during speech, survive slow Whisper, and disappear only when audio-linked text commits", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).lingualHardware.deferWhisper = true;
    (window as any).lingualHardware.preview("violet flowers");
  });
  const preview = page.getByLabel("Uncommitted speech");
  await expect(preview).toHaveText("violet flowers");
  await expect(preview).toHaveCSS("color", "rgb(166, 169, 191)");
  await expect(page.getByLabel("Entry text")).toHaveValue("");
  await say(page, "violet flowers are growing");
  await expect(preview).toHaveText("violet flowers are growing");
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as any).lingualHardware.whisperReplies.length,
      ),
    )
    .toBe(1);
  await page.evaluate(() => (window as any).lingualHardware.finishWhisper());
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "violet flowers are growing",
  );
  await expect(preview).toHaveCount(0);
  await expect(page.locator(".has-audio")).toHaveCount(4);
});

test("a spoken action gets provisional words then visible recognition without waiting for Whisper", async ({
  page,
}) => {
  await page.evaluate(() => {
    (window as any).lingualHardware.deferWhisper = true;
    (window as any).lingualHardware.preview("play");
  });
  await expect(page.getByLabel("Uncommitted speech")).toHaveText("play");
  await expect(page.getByLabel("Voice action recognized")).toHaveCount(0);
  await say(page, "play note");
  await expect(page.getByLabel("Voice action recognized")).toContainText(
    "play entry",
  );
  await expect(page.getByLabel("Voice action recognized")).toHaveCSS(
    "color",
    "rgb(255, 255, 255)",
  );
  await expect(page.getByLabel("Entry text")).toHaveValue("");
  await expect(page.getByLabel("Uncommitted speech")).toHaveCount(0);
  expect(
    await page.evaluate(
      () => (window as any).lingualHardware.whisperReplies.length,
    ),
  ).toBe(0);
});

test("a command prefix followed by prose never executes prematurely", async ({
  page,
}) => {
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("play note"),
  );
  await expect(page.getByLabel("Uncommitted speech")).toHaveText("play note");
  await expect(page.getByLabel("Voice action recognized")).toHaveCount(0);
  await say(page, "play note is what I said yesterday");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "play note is what I said yesterday",
  );
  await expect(page.getByLabel("Voice action recognized")).toHaveCount(0);
});

test("only buffer words turn gray when inserting speech in an existing entry", async ({
  page,
}) => {
  await say(page, "violet flowers bloom");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "violet flowers bloom",
  );
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Resume entry", exact: true })
    .waitFor();
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  await page
    .getByLabel("Entry text")
    .evaluate((element: HTMLTextAreaElement) => {
      element.focus();
      element.setSelectionRange(7, 7);
      element.dispatchEvent(new Event("select", { bubbles: true }));
      document.dispatchEvent(new Event("selectionchange"));
    });
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("beautiful"),
  );
  await expect(page.getByLabel("Audio-linked transcript")).toHaveText(
    "violet beautiful flowers bloom",
  );
  await expect(page.locator(".provisional-speech .has-audio")).toHaveCount(0);
  await expect(page.locator(".has-audio")).toHaveCount(3);
  await expect(page.getByLabel("Entry text")).toHaveValue(
    "violet flowers bloom",
  );
});

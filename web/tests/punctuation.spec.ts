import { test, expect } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { installSpeechHardware, record, select, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
});

test("voice controls have a centered primary action, grouped details, and separate voice actions", async ({
  page,
}) => {
  const newEntry = page.getByRole("button", { name: "New entry", exact: true });
  await expect(newEntry.locator("svg")).toHaveCount(1);
  await expect(newEntry).toHaveText("New entry");
  await expect(newEntry).toHaveCSS("background-color", "rgb(216, 119, 54)");
  await expect(newEntry).toHaveCSS("color", "rgb(255, 255, 255)");
  for (const ready of [false, true]) {
    if (ready)
      await page
        .getByRole("button", { name: "Enable voice", exact: true })
        .click();
    const button = page.getByRole("button", {
      name: ready ? "Start entry" : "Enable voice",
      exact: true,
    });
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 1000 });
      await expect(button).toBeVisible();
      await expect(
        page.getByText("Speak to add to this entry", { exact: true }),
      ).toHaveCount(0);
      await expect(page.locator(".waveform")).toHaveCount(0);
      const parent = await page.locator(".voice-console").boundingBox();
      const bounds = await button.boundingBox();
      const details = await page.locator(".speech-details").boundingBox();
      const secondary = await page
        .locator(".voice-console-bottom")
        .boundingBox();
      expect(
        Math.abs(bounds!.x + bounds!.width / 2 - parent!.x - parent!.width / 2),
      ).toBeLessThan(2);
      expect(details!.y).toBeGreaterThanOrEqual(bounds!.y + bounds!.height + 6);
      expect(secondary!.y).toBeGreaterThanOrEqual(
        details!.y + details!.height + 16,
      );
      await expect(button).toHaveCSS("color", "rgb(255, 255, 255)");
      await page.screenshot({
        path: `../.local/voice-hierarchy-${ready ? "ready" : "enable"}-${width}.png`,
        fullPage: true,
        animations: "disabled",
      });
    }
  }
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await expect(page.locator(".recording-time")).toBeVisible();
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
});

test("Whisper punctuation survives view changes, preferences, copying, undo, reload and export", async ({
  page,
}) => {
  const text = "Wait — really? “Yes…” It costs 3.14.";
  const clean = "Wait really Yes It costs 3.14";
  await record(page, text);
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await expect(page.locator(".transcript-word")).toHaveCount(6);
  await expect(page.locator(".transcript-word.missing-audio")).toHaveCount(0);
  await expect(
    page.locator(".transcript-word").filter({ hasText: /^—$/ }),
  ).toHaveCount(0);
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await page
    .getByRole("checkbox", { name: /Punctuation suggestions/ })
    .uncheck();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await expect(page.locator(".timeline-text")).toHaveText(clean);
  await select(page, 0, clean.length);
  await page
    .getByRole("button", { name: "Copy selection", exact: true })
    .click();
  await select(page, clean.length, clean.length);
  await page.getByRole("button", { name: "Paste Lingual clipboard" }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    `${clean} ${clean}`,
  );
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    clean,
  );
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  await page.reload();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    clean,
  );
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export text", exact: true }).click();
  const path = await (await download).path();
  expect(await readFile(path!, "utf8")).toBe(clean);
  // Selecting a later word must still cut its original audio unit after earlier punctuation disappeared.
  await select(page, clean.indexOf("costs"), clean.indexOf("costs") + 5);
  await page
    .getByRole("button", { name: "Cut selection", exact: true })
    .click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "Wait really Yes It 3.14",
  );
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await page.getByRole("checkbox", { name: /Punctuation suggestions/ }).check();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    text,
  );
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await expect(page.locator(".transcript-word.missing-audio")).toHaveCount(0);
});

test("punctuation Echo and rate changes keep highlights on the original word", async ({
  page,
}) => {
  await record(page, "Wait — really?");
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await page
    .getByRole("checkbox", { name: "Punctuation", exact: true })
    .check();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await page
    .getByRole("button", { name: "Audio-linked view", exact: true })
    .click();
  await page.getByRole("button", { name: "Read it back", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Pause echo", exact: true }),
  ).toBeVisible();
  await page.evaluate(() => {
    const hardware = (window as any).lingualHardware;
    hardware.boundary(hardware.utterances.at(-1).text.indexOf("really"), 6);
  });
  await expect(page.locator(".transcript-word.word-playing")).toHaveText(
    "really?",
  );
  await page
    .locator(".playback-controls")
    .getByRole("button", { name: "+", exact: true })
    .click();
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as any).lingualHardware.utterances.at(-1).text,
      ),
    )
    .toMatch(/^really/);
  await page.evaluate(() => (window as any).lingualHardware.boundary(0, 6));
  await expect(page.locator(".transcript-word.word-playing")).toHaveText(
    "really?",
  );
});

test("new dictation respects punctuation off and inserts before a hidden opening quote", async ({
  page,
}) => {
  await record(page, "“Hello” “world”");
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await page
    .getByRole("checkbox", { name: /Punctuation suggestions/ })
    .uncheck();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await select(page, 0, 0);
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, "Before!");
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    "Before Hello world",
  );
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await page.getByRole("checkbox", { name: /Punctuation suggestions/ }).check();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "Before! “Hello” “world”",
  );
});

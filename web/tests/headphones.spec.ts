import { test, expect } from "@playwright/test";
import { command, installSpeechHardware, record, select } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.addInitScript(() =>
    localStorage.setItem(
      "lingual-preferences",
      JSON.stringify({
        passiveEcho: false,
        voiceFeedback: false,
        headphones: false,
      }),
    ),
  );
  await page.goto("/");
});

test("Settings explains headphone-dependent options and clears feedback when headphones connect", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "Settings" });
  const reminder = page.getByRole("status", { name: "Headphones needed" });
  await expect(reminder).toHaveCount(0);
  await dialog
    .getByRole("checkbox", { name: "Passive Echo", exact: true })
    .check();
  await expect(reminder).toContainText("Connect headphones");
  await expect(reminder).toContainText("hear passive echo");
  await expect(
    dialog.getByRole("checkbox", { name: "Headphones", exact: true }),
  ).toHaveCount(0);
  await reminder.scrollIntoViewIfNeeded();
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(390);
  await page.screenshot({ path: info.outputPath("headphones-settings.png") });
  await dialog
    .getByRole("checkbox", { name: "Passive Echo", exact: true })
    .uncheck();
  await expect(reminder).toHaveCount(0);
  await dialog
    .getByRole("checkbox", { name: "Voice Feedback", exact: true })
    .check();
  await expect(reminder).toContainText("hear spoken feedback");
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - AirPods Pro"),
  );
  await expect(reminder).toHaveCount(0);
});

test("selection and Walk explain the missing audio while ordinary dictation remains usable", async ({
  page,
}) => {
  const reminder = page.getByRole("status", { name: "Headphones needed" });
  await record(page, "one two three");
  await expect(reminder).toHaveCount(0);
  await select(page, 4, 7);
  await expect(reminder).toContainText("repeat the selected audio");
  await command(page, "remove selection");
  await expect(reminder).toHaveCount(0);
  await page.getByRole("button", { name: "Walk", exact: true }).click();
  await expect(reminder).toContainText("hear audio while walking or running");
  await command(page, "exit walk");
  await command(page, "activate passive echo");
  await expect(reminder).toContainText("hear passive echo");
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - AirPods Pro"),
  );
  await expect(reminder).toHaveCount(0);
});

test("enabled echo and feedback show the reminder without blocking listening", async ({
  page,
}) => {
  await page
    .getByRole("button", { name: "Settings", exact: true })
    .last()
    .click();
  await page
    .getByRole("dialog")
    .getByRole("checkbox", { name: "Passive Echo", exact: true })
    .check();
  await page
    .getByRole("dialog")
    .getByRole("checkbox", { name: "Voice Feedback", exact: true })
    .check();
  await page.getByRole("button", { name: "Close dialog", exact: true }).click();
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  const reminder = page.getByRole("status", { name: "Headphones needed" });
  await expect(reminder).toContainText("hear passive echo");
  await expect(
    page.getByRole("button", { name: "Stop listening", exact: true }),
  ).toBeEnabled();
});

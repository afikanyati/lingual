import { test, expect } from "@playwright/test";
import {
  command,
  installSpeechHardware,
  record,
  say,
  select,
} from "./hardware";

test("selecting during dictation listens for actions; clearing selection resumes dictation", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await select(page, 4, 7);
  await expect(page.locator(".voice-console")).toContainText("Listening only");
  await say(page, "this must not replace two");
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    "one two three",
  );
  await command(page, "remove selection");
  await expect(page.locator(".voice-console")).toContainText(
    "Recording this entry",
  );
  await say(page, "added");
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    /added/,
  );
});

test("headphone selection repeats original audio and clearing selection cancels it", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.addInitScript(() =>
    localStorage.setItem(
      "lingual-preferences",
      JSON.stringify({ headphones: true, passiveEcho: false }),
    ),
  );
  await page.goto("/");
  await record(page, "one two three");
  const playbackStarts = () =>
    page.evaluate(
      () => (window as any).lingualHardware.playbackStarts as number,
    );
  const beforeSelection = await playbackStarts();
  await select(page, 4, 7);
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - AirPods Pro"),
  );
  // Each fixture word is only 100 ms long. Count real audio starts instead of
  // polling for a Pause button that may disappear between polling intervals.
  await expect.poll(playbackStarts).toBeGreaterThanOrEqual(beforeSelection + 3);
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - Speakers"),
  );
  await expect(
    page.getByRole("status", { name: "Headphones needed" }),
  ).toContainText("repeat the selected audio");
  const disconnected = await playbackStarts();
  await page.waitForTimeout(1300);
  expect(await playbackStarts()).toBe(disconnected);
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - AirPods Pro"),
  );
  await expect.poll(playbackStarts).toBeGreaterThan(disconnected);
  await command(page, "remove selection");
  await expect(
    page.locator(".playback-controls").getByRole("button", { name: /Pause/ }),
  ).toHaveCount(0);
  const afterClearing = await playbackStarts();
  await page.waitForTimeout(1300);
  expect(await playbackStarts()).toBe(afterClearing);
});

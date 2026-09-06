import { test, expect } from "@playwright/test";
import { installSpeechHardware, record } from "./hardware";

test("entry search uses one icon and button explanations work on hover and keyboard focus", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("textbox", { name: "Search entries" }),
  ).toHaveAttribute("placeholder", "Find an entry…");
  await expect(page.locator(".search svg")).toHaveCount(1);
  await expect(page.locator(".search span")).toHaveCount(0);
  await expect(page.locator(".voice-console .on-device")).toHaveCount(0);
  await expect(page.locator(".speech-details")).toContainText(
    "First-use download: ~109 MB",
  );
  await expect(page.locator(".speech-details")).toContainText(
    "No account or subscription",
  );
  await expect(page.locator(".speech-details")).toContainText(
    "Transcribed on your device",
  );
  await expect(
    page.getByText(/LESS FRICTION|MADE FOR YOUR OWN PACE/),
  ).toHaveCount(0);
  await expect(
    page.locator("button:not([data-tooltip]), button[data-tooltip='']"),
  ).toHaveCount(0);
  const transcript = page.getByRole("button", {
    name: "Transcript",
    exact: true,
  });
  await transcript.hover();
  await expect(page.getByRole("tooltip")).toContainText("typing is disabled");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("tooltip")).toHaveCount(0);
  const linked = page.getByRole("button", {
    name: "Audio-linked view",
    exact: true,
  });
  await linked.focus();
  await expect(page.getByRole("tooltip")).toContainText("Shift-click a range");
  const id = await page.getByRole("tooltip").getAttribute("id");
  await expect(linked).toHaveAttribute("aria-describedby", id!);
  await page.getByRole("textbox", { name: "Search entries" }).focus();
  await expect(page.getByRole("tooltip")).toHaveCount(0);
  // Disabled actions still need explanations before the first recording exists.
  await page.getByRole("button", { name: "Play", exact: true }).hover();
  await expect(page.getByRole("tooltip")).toHaveText(
    "Play this entry using your original recorded voice.",
  );
});

test("tooltips cover changing controls, recorded words, and the action dictionary", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  await page.getByRole("button", { name: "Resume entry", exact: true }).hover();
  await expect(page.getByRole("tooltip")).toContainText(
    "Add your next spoken words and audio to the selected entry",
  );
  await page
    .getByRole("button", { name: "Audio-linked view", exact: true })
    .click();
  await page.getByRole("button", { name: "two", exact: true }).hover();
  await expect(page.getByRole("tooltip")).toContainText(
    "Recorded · 0.10–0.20s",
  );
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await expect(page.locator(".command-palette button")).toHaveCount(92);
  for (const example of await page
    .locator(".help-commands code")
    .allTextContents()) {
    await expect(
      page
        .locator(".command-palette")
        .getByRole("button", { name: `${example} ↗`, exact: true }),
    ).toHaveCount(1);
  }
  await expect(
    page.locator("button:not([data-tooltip]), button[data-tooltip='']"),
  ).toHaveCount(0);
  await page
    .locator(".command-palette")
    .getByRole("button", { name: "play entry ↗", exact: true })
    .focus();
  await expect(page.getByRole("tooltip")).toHaveText(
    "Initiate playback of a selected entry.",
  );
  await page.getByRole("button", { name: "Close dialog" }).click();
  await expect(page.getByRole("tooltip")).toHaveCount(0);
});

test("tooltips stay inside a narrow viewport and disappear when the page scrolls", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("button", { name: "Toggle entry library" }).focus();
  const tooltip = page.getByRole("tooltip");
  await expect(tooltip).toBeVisible();
  const bounds = (await tooltip.boundingBox())!;
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(390);
  await expect(tooltip).toHaveCSS("background-color", "rgb(37, 37, 51)");
  await page.evaluate(() => window.dispatchEvent(new Event("scroll")));
  await expect(tooltip).toHaveCount(0);
});

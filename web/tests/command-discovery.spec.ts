import { test, expect } from "@playwright/test";
import { installSpeechHardware, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
});

test("a compact guide explains starting versus creating and opens the full dictionary", async ({
  page,
}) => {
  const guide = page.getByRole("region", { name: "Voice command guide" });
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await expect(guide).toContainText("start entry");
  await expect(guide).toContainText("Record a new entry");
  await expect(guide).toContainText("resume entry");
  await expect(guide).toContainText("Add to this entry");
  await guide.getByRole("button", { name: "All voice actions" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
});

for (const width of [320, 390, 1280]) {
  test(`live command completions highlight only heard words at ${width}px`, async ({
    page,
  }, info) => {
    await page.setViewportSize({ width, height: 844 });
    await page
      .getByRole("button", { name: "Enable voice", exact: true })
      .click();
    await page
      .getByRole("button", { name: "Resume entry", exact: true })
      .click();
    await expect(
      page.getByText("Recording this entry", { exact: true }),
    ).toBeVisible();
    await page.evaluate(() => (window as any).lingualHardware.preview("start"));
    const suggestions = page.getByRole("region", {
      name: "Possible voice commands",
    });
    await expect(suggestions).toContainText("entry");
    await expect(suggestions.locator("mark").first()).toHaveText("start");
    await expect(suggestions.locator("mark").first()).toHaveCSS(
      "background-color",
      "rgb(216, 119, 54)",
    );
    await expect(suggestions.locator("mark").first()).toHaveCSS(
      "color",
      "rgb(255, 255, 255)",
    );
    await expect(suggestions.locator(".command-remaining").first()).toHaveCSS(
      "color",
      "color(srgb 0.398039 0.403922 0.47451)",
    );
    await expect(page.getByLabel("Voice action recognized")).toHaveCount(0);
    await expect(page.getByLabel("Entry text")).toHaveValue("");
    await suggestions.scrollIntoViewIfNeeded();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBeLessThanOrEqual(width);
    await page.screenshot({
      path: info.outputPath("command-completions.png"),
      fullPage: true,
    });
    await page.evaluate(() =>
      (window as any).lingualHardware.preview("activate punctuation"),
    );
    await expect(suggestions).toContainText("suggestions");
    await expect(suggestions.locator("mark").last()).toHaveText(
      "activate punctuation",
    );
    await page.evaluate(() =>
      (window as any).lingualHardware.preview("start thinking about tomorrow"),
    );
    await expect(suggestions).toHaveCount(0);
    await page.evaluate(() => (window as any).lingualHardware.preview("start"));
    await expect(suggestions).toBeVisible();
    await page
      .getByRole("button", { name: "Voice actions on", exact: true })
      .click();
    await expect(suggestions).toHaveCount(0);
    await expect(
      page.getByRole("region", { name: "Voice command guide" }),
    ).toHaveCount(0);
    await page
      .getByRole("button", { name: "Voice actions off", exact: true })
      .click();
    await expect(suggestions).toHaveCount(0);
    await page.evaluate(() => (window as any).lingualHardware.preview("stop"));
    await expect(suggestions).toContainText("entry");
    await say(page, "stop entry");
    await expect(page.getByLabel("Voice action recognized")).toContainText(
      "stop entry",
    );
    await expect(suggestions).toHaveCount(0);
    await expect(page.getByLabel("Entry text")).toHaveValue("");
  });
}

test("completed command results do not revive suggestions from an earlier utterance", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("activate punctuation"),
  );
  await expect(
    page.getByRole("region", { name: "Possible voice commands" }),
  ).toBeVisible();
  await say(page, "activate punctuation");
  await expect(page.getByLabel("Voice action recognized")).toContainText(
    "activate punctuation",
  );
  await expect(
    page.getByRole("region", { name: "Possible voice commands" }),
  ).toHaveCount(0);
  await page.evaluate(() => (window as any).lingualHardware.preview("start"));
  await expect(
    page.getByRole("region", { name: "Possible voice commands" }),
  ).toContainText("start");
  await expect(page.getByLabel("Voice action recognized")).toHaveCount(0);
});

test("the everyday guide stays focused on whole entries after selecting recorded words", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, "One small thought");
  await expect(page.getByLabel("Entry text")).toHaveValue("One small thought");
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("SELECT_WORD");
  const guide = page.getByRole("region", { name: "Voice command guide" });
  for (const phrase of [
    "start entry",
    "resume entry",
    "play entry",
    "stop entry",
  ])
    await expect(guide).toContainText(phrase);
  for (const phrase of [
    "play selection",
    "update selection",
    "remove selection",
    "select word",
  ])
    await expect(guide).not.toContainText(phrase);
  await expect(
    page.getByText("Just between you and you.", { exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByText("Your entries stay in this browser.", { exact: true }),
  ).toHaveCount(1);
});

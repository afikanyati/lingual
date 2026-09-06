import { test, expect } from "@playwright/test";
import { installSpeechHardware, record, select, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "One small thought");
});

for (const width of [320, 1280]) {
  test(`selection suggests usable actions without speech at ${width}px`, async ({
    page,
  }, info) => {
    await page.setViewportSize({ width, height: 844 });
    await page
      .getByRole("button", { name: "Voice actions on", exact: true })
      .click();
    const suggestions = page.getByRole("region", {
      name: "Suggested selection actions",
    });
    await expect(suggestions).toHaveCount(0);
    await select(page, 4, 9);
    await expect(suggestions.getByRole("button")).toHaveCount(5);
    await expect(suggestions.locator("mark")).toHaveCount(0);
    await expect(page.getByLabel("Entry text")).toHaveValue(
      "One small thought",
    );
    await suggestions.scrollIntoViewIfNeeded();
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth),
    ).toBeLessThanOrEqual(width);
    await page.screenshot({
      path: info.outputPath("selection-suggestions.png"),
      fullPage: true,
      animations: "disabled",
    });
    await suggestions
      .getByRole("button", { name: "remove selection", exact: true })
      .click();
    await expect(suggestions).toHaveCount(0);
    await expect(page.getByLabel("Entry text")).toHaveValue(
      "One small thought",
    );
    await select(page, 4, 9);
    await suggestions
      .getByRole("button", { name: "delete selection", exact: true })
      .click();
    await expect(page.getByLabel("Entry text")).toHaveValue("One  thought");
    await page.getByRole("button", { name: "Undo", exact: true }).click();
    await expect(page.getByLabel("Entry text")).toHaveValue(
      "One small thought",
    );
  });
}

test("spoken completions take priority and selection actions return after a command", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await select(page, 4, 9);
  await expect(
    page.getByRole("region", { name: "Listening only" }),
  ).toBeVisible();
  const selections = page.getByRole("region", {
    name: "Suggested selection actions",
  });
  await expect(selections).toBeVisible();
  await page.evaluate(() => (window as any).lingualHardware.preview("copy"));
  const completions = page.getByRole("region", {
    name: "Possible voice commands",
  });
  await expect(completions.locator("mark")).toHaveText("copy");
  await expect(selections).toHaveCount(0);
  await say(page, "copy selection");
  await expect(page.getByLabel("Voice action recognized")).toContainText(
    "copy selection",
  );
  await expect(completions).toHaveCount(0);
  await expect(selections).toBeVisible();
  await selections
    .getByRole("button", { name: "update selection", exact: true })
    .click();
  await expect(page.getByLabel("Replacement text")).toBeVisible();
  await expect(selections).toHaveCount(0);
});

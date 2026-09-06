import { test, expect } from "@playwright/test";
import { installSpeechHardware, record, select } from "./hardware";

test("edits, persists, searches, exports and deletes entries", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await expect(page.getByRole("textbox", { name: "Entry text" })).toBeVisible();
  await record(page, "A little room to think.");
  await expect(page.getByText("Saved on this device")).toBeVisible();
  await page.reload();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "A little room to think.",
  );
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "",
  );
  await page.getByRole("button", { name: "Redo", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "A little room to think.",
  );
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export text", exact: true }).click();
  expect((await download).suggestedFilename()).toMatch(/\.txt$/);
  await page.getByRole("button", { name: "New entry" }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "",
  );
  await record(page, "Second thought");
  await page
    .getByRole("textbox", { name: "Search entries" })
    .fill("little room");
  await expect(
    page.getByRole("navigation", { name: "Entries" }).getByRole("button"),
  ).toHaveCount(1);
  await page
    .getByRole("navigation", { name: "Entries" })
    .getByRole("button")
    .click();
  await page.getByRole("button", { name: "Entry options" }).click();
  await page.getByRole("button", { name: "Delete entry", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByRole("button", { name: "Keep entry" }).click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "A little room to think.",
  );
});

test("selection clipboard and redo keep the editor usable", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  const editor = page.getByRole("textbox", { name: "Entry text" });
  await record(page, "One two three");
  await select(page, 4, 7);
  await page.getByRole("button", { name: "Cut selection" }).click();
  await expect(editor).toHaveValue("One  three");
  await page.getByRole("button", { name: "Paste Lingual clipboard" }).click();
  await expect(editor).toHaveValue("One two three");
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(editor).toHaveValue("One  three");
  await page.getByRole("button", { name: "Redo", exact: true }).click();
  await expect(editor).toHaveValue("One two three");
});

test("shows download errors rather than pretending to listen", async ({
  page,
  context,
}) => {
  await context.route("**/speech/**", (route) =>
    route.fulfill({ status: 503, body: "Model host unavailable" }),
  );
  await page.goto("/");
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await expect(page.getByRole("alert")).toBeVisible({ timeout: 20000 });
  await expect(
    page.getByRole("button", { name: "Enable voice", exact: true }),
  ).toBeEnabled();
});

test("mobile editor fits the viewport and guidance is accessible", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await expect(page.getByRole("textbox", { name: "Entry text" })).toBeVisible();
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(390);
  await page.getByRole("button", { name: "Toggle entry library" }).click();
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.getByRole("button", { name: "Close dialog" }).click();
  await page
    .getByRole("button", { name: "Close entry library", exact: true })
    .click();
  await expect(page.getByRole("textbox", { name: "Entry text" })).toBeVisible();
  await page.screenshot({ path: "../.local/mobile.png", fullPage: true });
});

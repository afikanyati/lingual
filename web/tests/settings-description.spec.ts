import { test, expect } from "@playwright/test";

test("Settings has a sans-serif heading, explains every control, and defaults punctuation on", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  const dialog = page.getByRole("dialog", { name: "Settings" });
  await expect(
    dialog.getByRole("heading", { name: "Settings", exact: true }),
  ).toHaveCSS("font-family", '"DM Sans", sans-serif');
  await expect(
    dialog.getByRole("checkbox", { name: "Punctuation", exact: true }),
  ).toBeChecked();
  await expect(
    dialog.getByRole("checkbox", { name: "Headphones", exact: true }),
  ).toHaveCount(0);
  for (const row of await dialog.locator(".settings-row").all()) {
    await expect(row.locator("small")).not.toHaveText("");
  }
  await dialog
    .getByRole("checkbox", { name: "Punctuation", exact: true })
    .uncheck();
  await page.reload();
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await expect(
    page
      .getByRole("dialog")
      .getByRole("checkbox", { name: "Punctuation", exact: true }),
  ).not.toBeChecked();
});

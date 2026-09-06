import { test, expect, type Page } from "@playwright/test";
import { installSpeechHardware, record } from "./hardware";

/** Check the real document width, rather than concealing overflow with a clipped body. */
async function fitsScreen(page: Page) {
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual((await page.viewportSize())!.width);
}

for (const viewport of [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 768, height: 1024 },
  { width: 844, height: 390 },
  { width: 1024, height: 768 },
  { width: 1440, height: 900 },
]) {
  test(`editor, library and preferences fit ${viewport.width}×${viewport.height}`, async ({
    page,
  }, info) => {
    await page.setViewportSize(viewport);
    await installSpeechHardware(page);
    await page.goto("/");
    const compact = viewport.width <= 900;
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await fitsScreen(page);
    if (compact) {
      await expect(
        page.getByRole("complementary", { name: "Entry library" }),
      ).toHaveCount(0);
      const listen = page.getByRole("button", {
        name: "Enable voice",
        exact: true,
      });
      expect((await listen.boundingBox())!.height).toBeGreaterThanOrEqual(44);
      await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveCSS(
        "font-size",
        "16px",
      );
      await page.getByRole("button", { name: "Toggle entry library" }).click();
    }
    const library = page.getByRole("complementary", { name: "Entry library" });
    await expect(library).toBeVisible();
    await library
      .getByRole("button", { name: "Settings", exact: true })
      .click();
    const modal = page.getByRole("dialog");
    await expect(modal).toBeVisible();
    await fitsScreen(page);
    const bounds = (await modal.boundingBox())!;
    expect(bounds.x).toBeGreaterThanOrEqual(0);
    expect(bounds.x + bounds.width).toBeLessThanOrEqual(viewport.width);
    expect(bounds.y + bounds.height).toBeLessThanOrEqual(viewport.height);
    expect(
      await modal.evaluate(
        (element) => element.scrollWidth - element.clientWidth,
      ),
    ).toBeLessThanOrEqual(1);
    await modal
      .getByRole("combobox", { name: "Read-back voice" })
      .scrollIntoViewIfNeeded();
    if (compact)
      await expect(
        page.getByRole("button", { name: "Close dialog" }),
      ).toBeInViewport();
    await page.screenshot({
      path: info.outputPath("preferences.png"),
      fullPage: true,
    });
    await page.getByRole("button", { name: "Close dialog" }).click();
    if (compact)
      await page
        .getByRole("button", { name: "Close entry library", exact: true })
        .click();
    await page.screenshot({
      path: info.outputPath("editor.png"),
      fullPage: true,
    });
  });
}

test("phone drawer dismisses with Escape or the backdrop, contains focus, and adapts across resize", async ({
  page,
}) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  const toggle = page.locator(".mobile-library-toggle");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-expanded", "true");
  await expect(page.locator("body")).toHaveCSS("overflow", "hidden");
  for (let index = 0; index < 15; index++) {
    await page.keyboard.press("Tab");
    expect(
      await page.evaluate(() =>
        Boolean(document.activeElement?.closest(".library")),
      ),
    ).toBe(true);
  }
  await page.keyboard.press("Escape");
  await expect(toggle).toBeFocused();
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await toggle.click();
  await page
    .locator(".library-backdrop")
    .click({ position: { x: 380, y: 100 } });
  await expect(toggle).toBeFocused();
  await toggle.click();
  await page.setViewportSize({ width: 1200, height: 800 });
  await expect(page.locator(".library-backdrop")).toHaveCount(0);
  await expect(page.locator("body")).not.toHaveCSS("overflow", "hidden");
  await expect(
    page.getByRole("complementary", { name: "Entry library" }),
  ).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(
    page.getByRole("complementary", { name: "Entry library" }),
  ).toHaveCount(0);
});

test("phone recording, selection controls and recording downloads fit without horizontal scrolling", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "A recorded entry on a phone");
  await page
    .getByRole("button", { name: "Audio-linked view", exact: true })
    .click();
  await fitsScreen(page);
  for (const name of ["Play", "Walk", "Run"]) {
    const button = page.getByRole("button", { name, exact: true });
    expect((await button.boundingBox())!.height).toBeGreaterThanOrEqual(44);
  }
  await page.getByRole("button", { name: "Recordings 1" }).click();
  await fitsScreen(page);
  await page.screenshot({
    path: info.outputPath("recorded-entry.png"),
    fullPage: true,
  });
});

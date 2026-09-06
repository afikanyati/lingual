import { test, expect } from "@playwright/test";

test("voice actions default on and remember an explicit off or on choice", async ({
  page,
}) => {
  await page.goto("/");
  const enabled = page.getByRole("button", {
    name: "Voice actions on",
    exact: true,
  });
  const disabled = page.getByRole("button", {
    name: "Voice actions off",
    exact: true,
  });
  await expect(enabled).toHaveAttribute("aria-pressed", "true");
  await enabled.click();
  await expect(disabled).toHaveAttribute("aria-pressed", "false");
  await expect
    .poll(() =>
      page.evaluate(() => localStorage.getItem("lingual-voice-actions")),
    )
    .toBe("false");
  await page.reload();
  await expect(disabled).toHaveAttribute("aria-pressed", "false");
  await disabled.click();
  await expect
    .poll(() =>
      page.evaluate(() => localStorage.getItem("lingual-voice-actions")),
    )
    .toBe("true");
  await page.reload();
  await expect(enabled).toHaveAttribute("aria-pressed", "true");
});

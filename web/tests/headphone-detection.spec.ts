import { test, expect } from "@playwright/test";
import { installSpeechHardware, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.addInitScript(() =>
    localStorage.setItem(
      "lingual-preferences",
      JSON.stringify({
        headphones: true,
        passiveEcho: true,
        voiceFeedback: false,
      }),
    ),
  );
  await page.goto("/");
});

test("passive echo follows headphone connection and disconnection without a mode", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  const reminder = page.getByRole("status", { name: "Headphones needed" });
  await expect(reminder).toContainText("Connect headphones");
  await expect(
    page.getByRole("button", {
      name: /wearing headphones|removed my headphones/,
    }),
  ).toHaveCount(0);
  await say(page, "Before headphones");
  await expect(page.getByLabel("Entry text")).toHaveValue("Before headphones");
  expect(
    await page.evaluate(
      () => (window as any).lingualHardware.utterances.length,
    ),
  ).toBe(0);

  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - Afika’s AirPods Pro"),
  );
  await expect(reminder).toHaveCount(0);
  await say(page, "After headphones");
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as any).lingualHardware.utterances.at(-1)?.text,
      ),
    )
    .toContain("After headphones");
  const before = await page.evaluate(() => ({
    spoken: (window as any).lingualHardware.utterances.length,
    cancelled: (window as any).lingualHardware.speechCancellations,
  }));
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - MacBook Pro Speakers"),
  );
  await expect(reminder).toBeVisible();
  await expect
    .poll(() =>
      page.evaluate(() => (window as any).lingualHardware.speechCancellations),
    )
    .toBeGreaterThan(before.cancelled);
  await say(page, "After disconnecting");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    /After disconnecting/,
  );
  expect(
    await page.evaluate(
      () => (window as any).lingualHardware.utterances.length,
    ),
  ).toBe(before.spoken);
  expect(
    await page.evaluate(() =>
      Object.hasOwn(
        JSON.parse(localStorage.getItem("lingual-preferences")!),
        "headphones",
      ),
    ),
  ).toBe(false);
});

test("hidden device information reports uncertainty and never revives a saved headphone preference", async ({
  page,
}) => {
  await page.evaluate(() => (window as any).lingualHardware.setOutput(""));
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  const reminder = page.getByRole("status", { name: "Headphones needed" });
  await expect(reminder).toContainText("can’t identify your audio output");
  await expect(
    page.getByRole("checkbox", { name: "Headphones", exact: true }),
  ).toHaveCount(0);
  await expect(
    page.getByRole("button", {
      name: /wearing headphones|removed my headphones/,
    }),
  ).toHaveCount(0);
  await page.evaluate(() =>
    (window as any).lingualHardware.setOutput("Default - USB Headset"),
  );
  await expect(reminder).toHaveCount(0);
  await page.reload();
  await page
    .getByRole("main")
    .getByRole("button", { name: "Settings", exact: true })
    .click();
  await expect(reminder).toContainText("Connect headphones");
});

test("microphone permission refreshes previously hidden output labels without a devicechange event", async ({
  page,
}) => {
  await page.evaluate(() => {
    const hardware = (window as any).lingualHardware;
    hardware.hideOutputUntilPermission = true;
    hardware.setOutput("Default - External Headphones");
  });
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("status", { name: "Headphones needed" }),
  ).toHaveCount(0);
  await say(page, "Headphones are available");
  await expect
    .poll(() =>
      page.evaluate(
        () => (window as any).lingualHardware.utterances.at(-1)?.text,
      ),
    )
    .toContain("Headphones are available");
});

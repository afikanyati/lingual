import { test, expect } from "@playwright/test";

test("production policy blocks injected scripts and external data requests", async ({
  page,
}) => {
  const response = await page.goto("/");
  expect(response?.headers()["content-security-policy"]).toContain(
    "frame-ancestors 'none'",
  );
  const result = await page.evaluate(async () => {
    const script = document.createElement("script");
    script.textContent = "document.documentElement.dataset.injected = 'yes'";
    document.body.append(script);
    let connectionBlocked = false;
    try {
      await fetch("https://example.invalid/security-probe");
    } catch {
      connectionBlocked = true;
    }
    return {
      injected: document.documentElement.dataset.injected,
      connectionBlocked,
    };
  });
  expect(result).toEqual({ injected: undefined, connectionBlocked: true });
});

test("entry titles from a backup remain text, never executable HTML", async ({
  page,
}) => {
  await page.goto("/");
  await page
    .getByRole("button", { name: "Settings", exact: true })
    .first()
    .click();
  const payload =
    '<img src=x onerror="document.documentElement.dataset.injected=1">';
  const entry = {
    id: "external",
    title: payload,
    text: "",
    spans: [],
    selection: { start: 0, end: 0 },
    history: [],
    future: [],
    clipIds: [],
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  await page
    .locator('input[type="file"]')
    .setInputFiles({
      name: "entry.json",
      mimeType: "application/json",
      buffer: Buffer.from(
        JSON.stringify({
          format: "lingual-web",
          version: 1,
          entries: [entry],
          clips: [],
        }),
      ),
    });
  await expect(page.getByText(payload, { exact: true }).first()).toBeVisible();
  expect(await page.locator('img[src="x"]').count()).toBe(0);
  expect(
    await page.evaluate(() => document.documentElement.dataset.injected),
  ).toBeUndefined();
});

test("the app cannot be embedded for clickjacking", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(
    () =>
      new Promise<void>((resolve) => {
        const frame = document.createElement("iframe");
        frame.onload = () => resolve();
        frame.src = location.href;
        document.body.append(frame);
      }),
  );
  await expect
    .poll(() =>
      page.evaluate(() => {
        const frame = document.querySelector("iframe");
        try {
          return (
            frame?.contentDocument?.querySelector("#root") !== null &&
            Boolean(frame?.contentDocument)
          );
        } catch {
          return false;
        }
      }),
    )
    .toBe(false);
});

test("only the Vosk worker receives the dynamic-code exception", async ({
  request,
}) => {
  const page = await request.get("/");
  const worker = await request.get("/speech/vosk-0.0.3/vosk.worker.js");
  expect(worker.status()).toBe(200);
  expect(worker.headers()["content-security-policy"]).toContain(
    "'unsafe-eval'",
  );
  expect(page.headers()["content-security-policy"]).not.toContain(
    "'unsafe-eval'",
  );
});

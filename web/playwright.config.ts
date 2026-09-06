import { defineConfig, devices } from "@playwright/test";
const port = Number(process.env.LINGUAL_E2E_PORT ?? 5175);
export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  globalTimeout: 180_000,
  workers: 2,
  fullyParallel: false,
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  webServer: {
    command: `yarn preview --port ${port} --strictPort`,
    url: `http://127.0.0.1:${port}`,
    // A stale preview may have different security headers; never silently reuse it.
    reuseExistingServer: false,
  },
  projects: [
    {
      name: "chromium",
      // Use the Chromium revision pinned to this Playwright release. Installed Chrome
      // can advance independently; the real speech harness verifies that browser separately.
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});

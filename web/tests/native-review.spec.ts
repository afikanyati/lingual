import { test, expect } from "@playwright/test";
import {
  command,
  installSpeechHardware,
  record,
  say,
  select,
} from "./hardware";

test("paused loudspeaker echo hears Resume and completion restores interrupted dictation", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await command(page, "echo entry");
  await expect(page.locator(".voice-console")).not.toContainText(
    "Recording this entry",
  );
  await page.getByRole("button", { name: "Pause echo", exact: true }).click();
  await expect(page.locator(".voice-console")).toContainText("Listening only");
  await say(page, "resume echo");
  await expect(
    page.getByRole("button", { name: "Pause echo", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".voice-console")).not.toContainText(
    "Microphone on",
  );
  await page.evaluate(() => (window as any).lingualHardware.finishEcho());
  await expect(page.locator(".voice-console")).toContainText(
    "Recording this entry",
  );
  await say(page, "four");
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    "one two three four",
  );
});

test("entry echo suspends a walk and Stop restores the same word and command microphone", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  await command(page, "walk entry");
  await expect(page.locator(".browse-bar")).toContainText("Walk");
  await command(page, "echo entry");
  await expect(
    page.getByRole("button", { name: "Pause echo", exact: true }),
  ).toBeVisible();
  await command(page, "stop echo");
  await expect(page.locator(".browse-bar")).toContainText("Walk");
  await expect(page.locator(".voice-console")).toContainText("Listening only");
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  await page.getByRole("textbox", { name: "Entry text" }).click();
  await expect(page.locator(".browse-bar")).toHaveCount(0);
});

test("the original welcome is loaded on demand with playable audio and is never duplicated", async ({
  page,
}) => {
  await installSpeechHardware(page);
  const requests: string[] = [];
  page.on("request", (request) => requests.push(request.url()));
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Help", exact: true }),
  ).toBeVisible();
  expect(requests.some((url) => url.includes("/welcome/"))).toBe(false);
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page
    .getByRole("button", { name: "Open original welcome entry" })
    .click();
  await expect(page.locator(".transcript-word")).toHaveCount(1000);
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Pause playback", exact: true }),
  ).toBeVisible();
  await command(page, "stop playback");
  await expect(page.locator(".missing-audio")).toHaveCount(0);
  const downloads = requests.filter((url) => url.includes("/welcome/")).length;
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page
    .getByRole("button", { name: "Open original welcome entry" })
    .click();
  await expect(page.locator(".transcript-word")).toHaveCount(1000);
  expect(requests.filter((url) => url.includes("/welcome/")).length).toBe(
    downloads,
  );
  await page.reload();
  await page
    .getByRole("button", { name: "Audio-linked view", exact: true })
    .click();
  await expect(page.locator(".transcript-word")).toHaveCount(1000);
});

test("explicit playback uses the native play cue and errors use the native error cue", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  const played: string[] = [];
  page.on("request", (request) => played.push(request.url()));
  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect
    .poll(() => played.some((url) => url.endsWith("/sounds/play.wav")))
    .toBe(true);
  await page.route("**/welcome/manifest.json", (route) =>
    route.fulfill({ status: 500, body: "Unavailable" }),
  );
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page
    .getByRole("button", { name: "Open original welcome entry" })
    .click();
  await expect
    .poll(() => played.some((url) => url.endsWith("/sounds/error.wav")))
    .toBe(true);
});

test("reload returns to the older active entry and its selected recorded words", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await record(page, "one two three");
  await page.getByRole("button", { name: "New entry", exact: true }).click();
  await record(page, "another entry");
  await page
    .locator(".entry-card")
    .filter({ hasText: "one two three" })
    .click();
  await select(page, 4, 7);
  await expect
    .poll(() =>
      page.evaluate(
        () => JSON.parse(localStorage.getItem("lingual-session")!).selection,
      ),
    )
    .toEqual({ start: 4, end: 7 });
  await page.reload();
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    "one two three",
  );
  await expect
    .poll(() =>
      page
        .locator("textarea")
        .evaluate((element: HTMLTextAreaElement) => [
          element.selectionStart,
          element.selectionEnd,
        ]),
    )
    .toEqual([4, 7]);
});

test("gray dictation at the end of a long entry is scrolled into view", async ({
  page,
}) => {
  await installSpeechHardware(page);
  await page.goto("/");
  await page.getByRole("button", { name: "Help", exact: true }).click();
  await page
    .getByRole("button", { name: "Open original welcome entry" })
    .click();
  await expect(page.locator(".transcript-word")).toHaveCount(1000);
  await page.getByRole("button", { name: "Enable voice", exact: true }).click();
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await page.evaluate(() =>
    (window as any).lingualHardware.preview("new ending"),
  );
  await expect(page.getByLabel("Uncommitted speech")).toBeInViewport();
});

import { test, expect } from "@playwright/test";
import { installSpeechHardware, record, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.addInitScript(() => {
    const NativeAudio = window.Audio;
    const clips: any[] = [];
    Object.assign(window, {
      originalAudio: clips,
      nativeOriginalAudio: NativeAudio,
    });
    // Control just the original recording's media clock; all recording/storage and UI paths stay real.
    window.Audio = class {
      currentTime = 0;
      duration = 10;
      playbackRate = 1;
      volume = 1;
      paused = true;
      ontimeupdate?: () => void;
      onloadedmetadata?: () => void;
      onended?: () => void;
      onpause?: () => void;
      onplaying?: () => void;
      onerror?: () => void;
      fail = false;
      constructor(src: string) {
        if (!src?.startsWith("blob:")) return new NativeAudio(src) as any;
        clips.push(this);
      }
      play() {
        if (this.fail) return Promise.reject(new Error("Playback unavailable"));
        this.paused = false;
        this.onloadedmetadata?.();
        this.onplaying?.();
        return Promise.resolve();
      }
      pause() {
        this.paused = true;
        this.onpause?.();
      }
      advance(time: number) {
        this.currentTime = time;
        this.ontimeupdate?.();
      }
      finish() {
        this.currentTime = this.duration;
        this.onended?.();
      }
    } as any;
  });
  await page.goto("/");
  await record(page, "The first original recording");
});

test("recordings disclosure flips its chevron and progress tracks elapsed audio through pause, resume and completion", async ({
  page,
}, info) => {
  await page.setViewportSize({ width: 390, height: 844 });
  const toggle = page.getByRole("button", {
    name: "Recordings 1",
    exact: true,
  });
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-expanded", "true");
  await expect(toggle.locator(".recordings-chevron")).toHaveCSS(
    "transform",
    "matrix(-1, 0, 0, -1, 0, 0)",
  );
  await page
    .getByRole("button", { name: "Play recording 1", exact: true })
    .click();
  await page.evaluate(() => (window as any).originalAudio[0].advance(3));
  const progress = page.getByRole("progressbar", {
    name: "Recording 1 playback progress",
  });
  await expect(progress).toHaveAttribute("value", "3");
  await expect(progress).toHaveAttribute("max", "10");
  await expect(page.getByLabel("Recording 1 elapsed time")).toHaveText(
    "0:03 / 0:10",
  );
  await page
    .getByRole("button", { name: "Pause recording 1", exact: true })
    .click();
  await expect(progress).toHaveAttribute("value", "3");
  await page
    .getByRole("button", { name: "Play recording 1", exact: true })
    .click();
  expect(await page.evaluate(() => (window as any).originalAudio.length)).toBe(
    1,
  );
  await page.evaluate(() => (window as any).originalAudio[0].advance(7));
  await progress.scrollIntoViewIfNeeded();
  await page.screenshot({
    path: info.outputPath("recording-progress.png"),
    fullPage: true,
  });
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(390);
  await page.evaluate(() => (window as any).originalAudio[0].finish());
  await expect(progress).toHaveAttribute("value", "10");
  await expect(page.getByLabel("Recording 1 elapsed time")).toHaveText(
    "0:10 / 0:10",
  );
  await page
    .getByRole("button", { name: "Play recording 1", exact: true })
    .click();
  await expect(progress).toHaveAttribute("value", "0");
  await toggle.click();
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await expect(toggle.locator(".recordings-chevron")).toHaveCSS(
    "transform",
    "none",
  );
});

test("switching recordings ignores old callbacks and failed playback resets the controls", async ({
  page,
}) => {
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, "The second original recording");
  await expect(page.getByLabel("Entry text")).toHaveValue(
    /The second original recording/,
  );
  await page
    .getByRole("button", { name: "Stop listening", exact: true })
    .click();
  await page.getByRole("button", { name: "Recordings 2", exact: true }).click();
  await page
    .getByRole("button", { name: "Play recording 1", exact: true })
    .click();
  await page.evaluate(() => {
    const clip = (window as any).originalAudio[0];
    clip.advance(4);
    (window as any).lateEnd = clip.onended;
    (window as any).lateUpdate = clip.ontimeupdate;
  });
  await page
    .getByRole("button", { name: "Play recording 2", exact: true })
    .click();
  await page.evaluate(() => {
    (window as any).lateEnd();
    (window as any).lateUpdate();
    (window as any).originalAudio[1].advance(2);
  });
  await expect(page.getByLabel("Recording 2 elapsed time")).toHaveText(
    "0:02 / 0:10",
  );
  await expect(page.getByLabel("Recording 1 elapsed time")).toContainText(
    "0:00 /",
  );
  await page
    .getByRole("button", { name: "Pause recording 2", exact: true })
    .click();
  await page.evaluate(() => {
    (window as any).originalAudio[1].fail = true;
  });
  await page
    .getByRole("button", { name: "Play recording 2", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Pause recording 2", exact: true }),
  ).toHaveCount(0);
  await expect(page.getByLabel("Recording 2 elapsed time")).toContainText(
    "0:00 /",
  );
  await expect(page.getByRole("alert")).toContainText("Playback unavailable");
});

test("real browser audio advances the progress bar and finishes at the recording duration", async ({
  page,
}) => {
  await page.evaluate(() => {
    window.Audio = (window as any).nativeOriginalAudio;
  });
  await page.getByRole("button", { name: "Recordings 1", exact: true }).click();
  await page
    .getByRole("button", { name: "Play recording 1", exact: true })
    .click();
  const progress = page.getByRole("progressbar", {
    name: "Recording 1 playback progress",
  });
  await expect
    .poll(() =>
      progress.evaluate(
        (element: HTMLProgressElement) =>
          element.value > 0 && element.value === element.max,
      ),
    )
    .toBe(true);
  await expect(
    page.getByRole("button", { name: "Play recording 1", exact: true }),
  ).toBeVisible();
});

import { test, expect } from "@playwright/test";
import { installSpeechHardware, record, select, say } from "./hardware";

test.beforeEach(async ({ page }) => {
  await installSpeechHardware(page);
  await page.goto("/");
});

test("entry and replacement transcripts cannot acquire words from a keyboard or paste", async ({
  page,
}) => {
  const editor = page.getByRole("textbox", { name: "Entry text" });
  await expect(editor).toHaveAttribute("readonly", "");
  await expect(editor).toHaveAttribute("inputmode", "none");
  await expect(page.getByRole("textbox", { name: "Entry title" })).toHaveCount(
    0,
  );
  await expect(
    page.getByRole("button", { name: "Import audio", exact: true }),
  ).toHaveCount(0);
  await editor.focus();
  await page.keyboard.insertText("unrecorded typing");
  await expect(editor).toHaveValue("");
  await record(page, "one two three");
  await select(page, 5, 6);
  await page.keyboard.press("Backspace");
  await page.keyboard.insertText("unrecorded paste");
  await editor.evaluate((element) => {
    const data = new DataTransfer();
    data.setData("text/plain", "unrecorded drop");
    element.dispatchEvent(
      new DragEvent("drop", { dataTransfer: data, bubbles: true }),
    );
    element.dispatchEvent(
      new ClipboardEvent("paste", { clipboardData: data, bubbles: true }),
    );
  });
  await expect(editor).toHaveValue("one two three");
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("UPDATE_SELECTION");
  const draft = page.getByRole("textbox", { name: "Replacement text" });
  await expect(draft).toHaveAttribute("readonly", "");
  await draft.focus();
  await page.keyboard.insertText("unrecorded replacement");
  await expect(draft).toHaveValue("");
  await record(page, "new words", true);
  await page.getByRole("button", { name: "Accept replacement" }).click();
  await expect(editor).toHaveValue("one new words three");
  await expect(page.getByText("Saved on this device")).toBeVisible();
  await page.reload();
  await expect(editor).toHaveValue("one new words three");
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await expect(page.locator(".transcript-word.missing-audio")).toHaveCount(0);
  await expect(page.locator(".transcript-word")).toHaveCount(4);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await page.getByRole("button", { name: "Transcript", exact: true }).click();
  await expect(editor).toHaveValue("one two three");
});

test("partial-word deletion removes the whole recorded word and keeps undo audio", async ({
  page,
}) => {
  await record(page, "one two three");
  await select(page, 5, 6);
  await page
    .getByLabel("Selection action", { exact: true })
    .selectOption("DELETE_SELECTION");
  await expect(page.getByRole("textbox", { name: "Entry text" })).toHaveValue(
    "one  three",
  );
  await page.getByRole("button", { name: "Audio-linked view" }).click();
  await expect(page.locator(".transcript-word")).toHaveCount(2);
  await expect(page.locator(".transcript-word.missing-audio")).toHaveCount(0);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expect(page.locator(".transcript-word")).toHaveCount(3);
});

test("dictation preserves spoken punctuation names and literal phrases instead of inventing commands", async ({
  page,
}) => {
  await record(page, "comma new paragraph literal undo");
  await expect(
    page.getByRole("button", { name: "Voice actions on" }),
  ).toHaveAttribute("aria-pressed", "true");
  await page.getByRole("button", { name: "Resume entry", exact: true }).click();
  await expect(
    page.getByText("Recording this entry", { exact: true }),
  ).toBeVisible();
  await say(page, "literal undo");
  await expect(page.locator('textarea[aria-label="Entry text"]')).toHaveValue(
    "comma new paragraph literal undo literal undo",
  );
  await page.getByRole("button", { name: /Stop listening/i }).click();
});

for (const mixed of [false, true]) {
  test(`${mixed ? "partially recorded" : "unrecorded"} legacy text stays recoverable but is not synthesized by Play or copied`, async ({
    page,
  }) => {
    await record(page, "one two three");
    // Seed a pre-correction record; the app must retain it without treating its missing audio as speech.
    await page.evaluate(async (mixed) => {
      const db = await new Promise<IDBDatabase>((resolve) => {
        const request = indexedDB.open("lingual-local", 1);
        request.onsuccess = () => resolve(request.result);
      });
      const entries = await new Promise<any[]>((resolve) => {
        const request = db
          .transaction("entries")
          .objectStore("entries")
          .getAll();
        request.onsuccess = () => resolve(request.result);
      });
      const entry = entries[0];
      entry.spans = mixed ? entry.spans.slice(0, 1) : [];
      const tx = db.transaction("entries", "readwrite");
      tx.objectStore("entries").put(entry);
      await new Promise((resolve) => {
        tx.oncomplete = resolve;
      });
      db.close();
    }, mixed);
    await page.reload();
    const editor = page.getByRole("textbox", { name: "Entry text" });
    await expect(editor).toHaveValue("one two three");
    await page.getByRole("button", { name: "Play", exact: true }).click();
    await expect(
      page.getByText(/no complete original recording for this passage/),
    ).toBeVisible();
    expect(
      await page.evaluate(
        () => (window as any).lingualHardware.utterances.length,
      ),
    ).toBe(0);
    await select(page, 0, 13);
    await page
      .getByRole("button", { name: "Copy selection", exact: true })
      .click();
    await expect(page.getByText(/words without a recording/)).toBeVisible();
    await expect(
      page.getByRole("button", { name: "Paste Lingual clipboard" }),
    ).toBeDisabled();
    await page.reload();
    await expect(editor).toHaveValue("one two three");
  });
}

for (const action of ["Undo", "Redo", "keyboard undo"]) {
  test(`${action} cannot restore unrecorded legacy history`, async ({
    page,
  }) => {
    await record(page, "one two three");
    await page.evaluate(async (action) => {
      const db = await new Promise<IDBDatabase>((resolve) => {
        const request = indexedDB.open("lingual-local", 1);
        request.onsuccess = () => resolve(request.result);
      });
      const entries = await new Promise<any[]>((resolve) => {
        const request = db
          .transaction("entries")
          .objectStore("entries")
          .getAll();
        request.onsuccess = () => resolve(request.result);
      });
      const entry = entries[0];
      entry[action === "Redo" ? "future" : "history"] = [
        {
          text: "unrecorded legacy words",
          selection: { start: 0, end: 0 },
          spans: [],
        },
      ];
      const tx = db.transaction("entries", "readwrite");
      tx.objectStore("entries").put(entry);
      await new Promise((resolve) => {
        tx.oncomplete = resolve;
      });
      db.close();
    }, action);
    await page.reload();
    const editor = page.getByRole("textbox", { name: "Entry text" });
    await expect(editor).toHaveValue("one two three");
    if (action === "keyboard undo") {
      await editor.focus();
      await page.keyboard.press("ControlOrMeta+z");
    } else
      await page.getByRole("button", { name: action, exact: true }).click();
    await expect(page.getByText(/words without a recording/)).toBeVisible();
    await expect(editor).toHaveValue("one two three");
  });
}

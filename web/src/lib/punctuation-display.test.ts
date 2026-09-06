import { describe, expect, it } from "vitest";
import {
  punctuationPresentation,
  sourceSelection,
  displaySelection,
} from "./punctuation";
import { createEntry } from "./editor";
import { insertPassage, copyPassage } from "./timeline";
import { spokenPassage } from "../test/fixtures";
import { defaultPreferences } from "./commands";
import { presentedText } from "./prosody";

describe("punctuation visibility without losing source audio", () => {
  it("removes recognized punctuation and restores the exact original when enabled", () => {
    const text = "“Wait”—really? Yes… (Okay!)";
    expect(punctuationPresentation(text, false).text).toBe(
      "Wait really Yes Okay",
    );
    expect(punctuationPresentation(text, true).text).toBe(text);
  });
  it("keeps meaningful spelling and numbers, without joining words across punctuation", () => {
    expect(
      punctuationPresentation(
        "Don't re-enter at 3.14 or 12:30; hello,world!",
        false,
      ).text,
    ).toBe("Don't re-enter at 3.14 or 12:30 hello world");
  });
  it("maps a displayed selection and caret back to the recorded words", () => {
    const text = "“Wait”—really? Yes…";
    const view = punctuationPresentation(text, false);
    const selection = sourceSelection(view, { start: 5, end: 11 });
    expect(text.slice(selection.start, selection.end)).toBe("really");
    expect(displaySelection(view, selection)).toEqual({ start: 5, end: 11 });
    expect(
      sourceSelection(view, { start: view.text.length, end: view.text.length }),
    ).toEqual({ start: text.length, end: text.length });
    const entry = insertPassage(createEntry(), spokenPassage(text));
    expect(copyPassage(entry, selection).spans[0].sourceStart).toBe(
      entry.spans[0].sourceStart,
    );
  });
  it("places a caret before hidden opening quotes rather than inside the recorded word", () => {
    const view = punctuationPresentation("“Hello” “world”", false);
    expect(sourceSelection(view, { start: 0, end: 0 })).toEqual({
      start: 0,
      end: 0,
    });
    expect(sourceSelection(view, { start: 6, end: 6 })).toEqual({
      start: 8,
      end: 8,
    });
  });
  it("removes punctuation from export and Echo without changing stored text or spans", () => {
    const entry = insertPassage(
      createEntry(),
      spokenPassage("Wait — really? “Yes…”"),
    );
    const original = structuredClone(entry);
    const prefs = {
      ...defaultPreferences,
      punctuationSuggestions: false,
      punctuation: true,
    };
    expect(
      presentedText(entry, prefs, { start: 0, end: entry.text.length }),
    ).toBe("Wait really Yes");
    expect(
      presentedText(entry, prefs, { start: 0, end: entry.text.length }, true),
    ).toBe("Wait really Yes");
    expect(entry).toEqual(original);
  });
});

import { HeadphoneStatus } from "../enums/headphones";
import { expect, it } from "vitest";
import { defaultPreferences } from "./commands";
import { headphoneReminder } from "./headphone-reminder";

const preferences = {
  ...defaultPreferences,
  passiveEcho: false,
  voiceFeedback: false,
};
it("keeps normal dictation, playback, and idle preferences free of headphone requirements", () => {
  expect(headphoneReminder({ preferences })).toBe("");
  expect(headphoneReminder({ preferences, listening: true })).toBe("");
  expect(headphoneReminder({ preferences: defaultPreferences })).toBe("");
});
it("identifies every headphone-dependent review path", () => {
  expect(headphoneReminder({ preferences, selection: true })).toContain(
    "repeat the selected audio",
  );
  expect(headphoneReminder({ preferences, browsing: true })).toContain(
    "hear audio while walking or running",
  );
  expect(headphoneReminder({ preferences, handsFreePlayback: true })).toContain(
    "use voice actions during playback",
  );
});
it("explains enabled listening features both on activation and in Settings", () => {
  for (const state of [
    { listening: true },
    { settingsOpen: true },
    { requestedFeature: "passiveEcho" as const },
  ])
    expect(
      headphoneReminder({ preferences: defaultPreferences, ...state }),
    ).toContain("hear passive echo");
  expect(
    headphoneReminder({
      preferences: { ...preferences, voiceFeedback: true },
      requestedFeature: "voiceFeedback",
    }),
  ).toContain("hear spoken feedback");
});
it("clears the reminder when headphones are detected or the requested feature is disabled", () => {
  expect(
    headphoneReminder({
      preferences: defaultPreferences,
      headphoneStatus: HeadphoneStatus.Headphones,
      listening: true,
      selection: true,
      browsing: true,
      settingsOpen: true,
    }),
  ).toBe("");
  expect(
    headphoneReminder({ preferences, requestedFeature: "passiveEcho" }),
  ).toBe("");
});
it("combines requirements into one reminder without misrepresenting basic playback", () => {
  const text = headphoneReminder({
    preferences: defaultPreferences,
    listening: true,
    selection: true,
    browsing: true,
    handsFreePlayback: true,
  });
  expect(text.match(/Connect headphones/g)).toHaveLength(1);
  expect(text).not.toContain("Settings");
  expect(text).toContain("hear passive echo");
  expect(text).toContain("hear spoken feedback");
});

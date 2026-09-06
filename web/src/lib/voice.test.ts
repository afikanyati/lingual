import { expect, it } from "vitest";
import { chooseLocalVoice, SpeakerPitch } from "./voice";
const voice = (name: string, lang = "en-US", localService = true) => ({ name, lang, localService, voiceURI: name }) as SpeechSynthesisVoice;
it("uses the native acoustic register and locale preferences, never a remote voice", () => {
  const voices = [voice("Remote", "en-US", false), voice("Ava (Enhanced)"), voice("Tom (Enhanced)"), voice("Karen (Enhanced)", "en-AU"), voice("Lee (Enhanced)", "en-AU")];
  expect(chooseLocalVoice(voices, "", 220, "en-US")?.name).toBe("Tom (Enhanced)");
  expect(chooseLocalVoice(voices, "", 440, "en-AU")?.name).toBe("Karen (Enhanced)");
  expect(chooseLocalVoice(voices, "Lee (Enhanced)", 440, "en-US")?.name).toBe("Lee (Enhanced)");
  expect(chooseLocalVoice([voices[0]], "Remote", 220, "en-US")).toBeUndefined();
  expect(chooseLocalVoice([voice("English", "en-GB"), voice("Français", "fr-FR")], "", undefined, "en-GB")?.name).toBe("English");
});
it("calibrates only voiced samples, persists a stable baseline, and resets an unfinished session", () => {
  const pitch = new SpeakerPitch();
  for (let index = 0; index < 14; index++) expect(pitch.add(220)).toBeUndefined();
  expect(pitch.add(undefined)).toBeUndefined();
  expect(pitch.add(220)).toBe(220);
  expect(pitch.add(440)).toBe(220);
  expect(new SpeakerPitch(330).add(220)).toBe(330);
  const fresh = new SpeakerPitch();
  fresh.add(220);
  fresh.reset();
  for (let index = 0; index < 15; index++) fresh.add(440);
  expect(fresh.value).toBe(440);
});

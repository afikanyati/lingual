import type { WelcomeManifest } from "../interfaces/welcome";
import { hasCompleteAudio } from "./audio-integrity";
import { importRecords, loadEntries } from "./storage";

/** Load the native welcome recording on demand; never overwrite an edited copy or save text without audio. */
export async function openWelcome(): Promise<string> {
  const existing = (await loadEntries()).find(
    (entry) => entry.id === "native-welcome-v1",
  );
  if (existing) return existing.id;
  const base = `${import.meta.env.BASE_URL}welcome/`;
  const response = await fetch(`${base}manifest.json`);
  if (!response.ok)
    throw new Error("The original welcome entry could not be loaded.");
  const manifest: WelcomeManifest = await response.json();
  if (!hasCompleteAudio(manifest.entry))
    throw new Error("The welcome entry is missing its audio links.");
  const clips = await Promise.all(
    manifest.clips.map(async ({ file, ...clip }) => {
      if (!/^[A-Fa-f0-9-]+\.wav$/.test(file))
        throw new Error("Invalid welcome recording filename.");
      const result = await fetch(`${base}${file}`);
      if (!result.ok)
        throw new Error(
          "A welcome recording could not be downloaded. Please try again.",
        );
      return {
        ...clip,
        audio: new Blob([await result.arrayBuffer()], { type: "audio/wav" }),
      };
    }),
  );
  const ids = new Set(clips.map((clip) => clip.id));
  if (manifest.entry.spans.some((span) => !ids.has(span.clipId)))
    throw new Error("Missing welcome recording.");
  await importRecords([manifest.entry], clips);
  return manifest.entry.id;
}

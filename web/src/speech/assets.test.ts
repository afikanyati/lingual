import { describe, expect, it } from "vitest";
import { speechAssetURLs } from "./assets";
import manifest from "../config/speech-assets.json";

describe("static deployment speech assets", () => {
  it("uses the same HTTPS origin as Firebase Hosting", () => {
    const urls = speechAssetURLs("/", "https://lingual.example");
    expect(urls.models).toBe(
      `https://lingual.example/speech/${manifest.revision}/models/`,
    );
    expect(urls.runtime).toBe("https://lingual.example/speech/runtime-3.8.1/");
  });
  it("resolves against the deployed base path, not the worker assets directory", () => {
    const urls = speechAssetURLs("/lingual/", "https://static.example");
    expect(urls.models).toBe(
      `https://static.example/lingual/speech/${manifest.revision}/models/`,
    );
    expect(urls.runtime).toBe(
      "https://static.example/lingual/speech/runtime-3.8.1/",
    );
  });
});

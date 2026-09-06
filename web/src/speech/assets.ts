import manifest from "../config/speech-assets.json";

/** Resolve static model/runtime files from the app base, even though this code executes inside /assets/*.js. */
export function speechAssetURLs(base: string, origin: string) {
  const app = new URL(base, `${origin}/`);
  return {
    models: new URL(`speech/${manifest.revision}/models/`, app).href,
    runtime: new URL(`speech/runtime-${manifest.transformersVersion}/`, app)
      .href,
  };
}

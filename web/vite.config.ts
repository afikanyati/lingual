import { createReadStream } from "node:fs";
import { resolve } from "node:path";
import { defineConfig } from "vitest/config";
import hostingConfig from "../firebase.json";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [
    react(),
    {
      name: "hosting-worker-policy-preview",
      // Vosk's Emscripten bindings require dynamic code only in its isolated worker.
      // Serve that fixed asset with its Firebase policy so real speech tests cover the exception.
      configurePreviewServer(server) {
        server.middlewares.use((request, response, next) => {
          const rule = hostingConfig.hosting.headers.find((rule) =>
            rule.source.endsWith("vosk.worker.js"),
          )!;
          if (request.url?.split("?")[0] !== rule.source) return next();
          response.setHeader("Content-Type", "application/javascript");
          for (const header of [
            ...hostingConfig.hosting.headers[0].headers,
            ...rule.headers,
          ]) {
            response.setHeader(header.key, header.value);
          }
          const file = resolve(
            server.config.root,
            server.config.build.outDir,
            rule.source.slice(1),
          );
          createReadStream(file).on("error", next).pipe(response);
        });
      },
    },
  ],
  test: { include: ["src/**/*.test.ts"] },
  worker: { format: "es" },
  // Exercise the deployed browser policy in preview and browser tests, without blocking development HMR.
  preview: {
    headers: Object.fromEntries(
      hostingConfig.hosting.headers
        .filter((rule) => rule.source === "**")
        .flatMap((rule) => rule.headers)
        .map(({ key, value }) => [key, value]),
    ),
  },
  server: { port: 5173, strictPort: true },
});

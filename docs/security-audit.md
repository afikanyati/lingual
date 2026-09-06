# Lingual security audit — 2026-09-05

This is a source, dependency, browser-behavior and Firebase-configuration review, not a guarantee against compromise. Scope: the React application, its static speech assets, import/export and local persistence, build tooling, the live `lingual-notetaker.web.app` deployment, and security-sensitive paths in the original Swift app. No user recordings, subscriber data or CloudKit records were accessed; no destructive or load testing was performed.

## Findings and remediation

| Finding | Exposure and impact | Status |
| --- | --- | --- |
| Missing browser security headers | The live page lacked CSP and frame restrictions. Another site could embed the app for clickjacking; no CSP backstop existed against a future script-injection bug. This is hardening, not proof of an existing XSS exploit. | Deployed to `lingual-notetaker.web.app` in the follow-up release. Added CSP, framing denial, MIME sniffing protection, no-referrer and restricted feature permissions. |
| Malformed backup editing metadata | An imported entry with `commits: "not an array"` passed validation and was persisted, but later editing expects `.map`/`.flatMap`. Other optional metadata and non-string dates were unchecked. A user would have to import the crafted file; impact is local data integrity/availability, not access to another user's browser. | Deployed in the follow-up web release. Validate ranges, commits, selection scale, dates, span metadata and recording offsets before any transaction. Eight negative regression cases; rejected imports preserve existing entries. |
| Published dependency advisories | Original lockfile had 10 advisories: 1 critical, 5 high, 4 moderate. These are package ratings, **not deployed-app exploit ratings**. Vite/Vitest findings concern development servers, Playwright concerns browser installation, Sharp concerns native image processing, and UUID concerns particular buffer-taking APIs. | Updated Vite 7.3.6, Vitest 3.2.6, Playwright 1.55.1; pinned patched transitive UUID 11.1.1 and Sharp 0.35.4. Final Yarn audit reports zero known advisories. |
| Native CloudKit telemetry | `StorageManager.save` calls `saveToCloud`; the latter writes identity, pitch, usage history and serialized `VoiceCommandDatum.utteredSpeech` to `publicCloudDatabase`. | **Open, high-priority privacy/access-control review before native release.** CloudKit schema roles and deployed records were not accessible in this audit, so public readability is unverified. Do not infer that “public database” alone proves anonymous access. Recommend disabling this upload or designing explicit consent, data minimization and appropriate private storage; review existing server permissions and retention before changing/deleting records. |
| Native insecure archive decoding | `StorageManager` uses `unarchiveTopLevelObjectWithData` and archives with `requiringSecureCoding: false`; model initializers contain forced casts. | **Open defense-in-depth issue.** The inspected path loads sandboxed UserDefaults, not a remotely supplied archive. Migrate carefully to secure, allowlisted coding with backward-compatible recovery; switching a flag alone would break saved entries. |

## Browser policy and compatibility

The page permits scripts only from its own origin and WebAssembly compilation. It blocks inline JavaScript, string evaluation, external `fetch`/WebSocket destinations, forms, plugins and embedding. Inline styles remain permitted because the current React UI uses them. Google Fonts stylesheet/font origins remain permitted; these requests disclose ordinary connection metadata to Google, not recordings. Self-hosting fonts would remove that external dependency.

Vosk's Emscripten runtime dynamically constructs functions. Its **exact worker URL** has an `unsafe-eval` exception; the document does not. The worker still has same-origin connection restrictions. The real-model test initially failed under the stricter policy and was rerun with this narrow exception. This is why policy validation includes real speech, not just mocked browser workflows. The preview server mirrors the worker-specific policy; Hosting header precedence must also be verified after deployment.

The transitive overrides intentionally exceed the upstream exact/semver requests, so Yarn prints resolution warnings. Sharp is a Node dependency of Transformers, not a browser speech module. A native PNG encode/decode smoke test and the complete app/speech checks cover this update; a future upstream dependency update should remove the overrides when it includes these patched versions. No inference model or model runtime version was changed.

## Checks and boundaries

- Rendering: no `dangerouslySetInnerHTML`, direct HTML sink or app-level eval path was found in React source. Browser regression imports an HTML/event-handler title and verifies it remains text.
- Storage: IndexedDB entries and blobs are scoped to the origin. No shared database, login API, server session or remote entry identifier is used by this React app. Imports remap IDs and write transactionally; exports are local downloads.
- Files: the import UI rejects files over 256 MiB; very large valid archives can still consume substantial memory and storage. Imported audio is decoded by browser codecs. Backup validity is structural, not a cryptographic guarantee that the transcript was really spoken.
- Speech: Vosk and Whisper load static same-origin assets; remote model loading is disabled. Read-back explicitly chooses local system voices and refuses to fall back to a remote voice. Build downloads verify pinned model sizes and hashes. Microphone cancellation, stop and stale callbacks have regression coverage.
- Voice authorization: voice commands are **not speaker authentication**. Nearby people or another audio source may issue commands while listening is active. Pitch calibration does not establish identity. Destructive entry deletion already has a confirmation flow, but a voice confirmation is not proof of who spoke. Turn off listening/voice actions in an untrusted acoustic environment.
- Local confidentiality: this app has no password lock or application-level encryption. Someone using the same unlocked browser profile, a sufficiently privileged extension, or a compromised OS may read or modify data. JSON/audio backups are unencrypted. An authorized hosting deployer can replace the JavaScript and thereby gain access when a user next visits; protecting the owner account and deployment credentials matters.
- Firebase read-only checks: no `allUsers` or `allAuthenticatedUsers` project IAM grants; one owner binding and service-agent bindings. No Storage buckets or Realtime Database instances were listed. Firestore and Functions management calls reported `SERVICE_DISABLED`. No Firebase rules were changed, and there are no entry database rules to tighten in the present static architecture.
- Hosting: HTTPS/HSTS present. `/.git/config`, `/.env`, `/firebase.json`, `/src/App.tsx`, `/package.json` returned 404. Targeted credential-pattern scans of app source, scripts, native source and textual build assets found no matches. This was not a complete historical Git secret scan.
- Outside proof: CloudKit authorization, Apple account configuration, Google account MFA/recovery, inherited organization policies, historical leaked credentials, browser/OS zero-days, physical headphone routing and availability/billing-abuse resistance. Public model files can be downloaded repeatedly; Hosting quotas/bandwidth remain an operational consideration. No load test was run.

## Validation and release

Reproduce with:

```sh
yarn --cwd web audit
LINGUAL_E2E_PORT=5177 yarn test:predeploy
# In another terminal, serve the production build with the real Hosting policies:
yarn --cwd web preview --port 5176 --strictPort
LINGUAL_TEST_URL=http://127.0.0.1:5176 node scripts/verify-speech.mjs
```

`test:predeploy` includes the security header contract tests, native/source checks, web units and all browser tests. Browser tests now refuse to reuse a stale preview server; use `LINGUAL_E2E_PORT` if the default port is occupied. Final results: 382 web unit tests, 85 browser tests, two Hosting-policy tests and the native/source checks passed. The real Vosk/Whisper check passed with cold download, cached reload, provisional words, audio links, microphone release and no external speech requests or uploads. Final dependency audit: zero known advisories. Local logs are under `.local/logs/security-*`.

Follow-up release: the web fixes were deployed to `https://lingual-notetaker.web.app`. The live document and Vosk worker returned their expected distinct CSP headers, and the live HTML matched the production build. The original Swift telemetry and archive behavior remain unchanged. Full predeployment checks and 11 iOS simulator tests passed. Ruff/Vulture/Knip were run before committing: Ruff reported existing Python formatting issues, Vulture flagged standard tar metadata attributes, and Knip flagged dynamic/static tooling references and unnecessary interface exports; no cleanup deletion was included.

## Primary references

- [Vite development-server advisory](https://github.com/advisories/GHSA-p9ff-h696-f583)
- [Vitest API/UI advisory and affected configurations](https://github.com/advisories/GHSA-5xrq-8626-4rwp)
- [Playwright browser-download certificate advisory](https://github.com/advisories/GHSA-7mvr-c777-76hp)
- [Sharp/libvips advisory](https://github.com/advisories/GHSA-f88m-g3jw-g9cj)
- [esbuild Windows development-server advisory](https://github.com/advisories/GHSA-g7r4-m6w7-qqqr)

Live release verification: both `yarn test:speech` harnesses passed against `https://lingual-notetaker.web.app`, including cold/cached models, gray hypotheses, command feedback, paragraph pauses, trimmed audio export and microphone teardown. Evidence: `.local/logs/release-live-speech.log`.

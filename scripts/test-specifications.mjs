import { readFileSync, existsSync, writeFileSync } from "node:fs";

// Validate coverage accounting separately from behavioral test results. Never count this inventory as 184 passing tests.
const rows = JSON.parse(readFileSync(new URL("../docs/test-specifications.json", import.meta.url), "utf8"));
const allowed = new Set(["automated", "partial", "device", "gap", "adaptation", "refactor", "group"]);
if (rows.length !== 184) throw new Error("Every original note item must retain its stable LTS identifier.");
const counts = {};
for (const [index, row] of rows.entries()) {
  if (row.id !== `LTS-${String(index + 1).padStart(3, "0")}`) throw new Error(`Missing/duplicate/reordered ID: ${row.id}`);
  if (!allowed.has(row.status) || !row.note || !row.detail) throw new Error(`Incomplete classification: ${row.id}`);
  if (row.status === "automated" && !row.tests.length) throw new Error(`Missing test reference: ${row.id}`);
  for (const path of row.tests) if (!existsSync(new URL(`../${path}`, import.meta.url))) throw new Error(`Broken test link: ${path}`);
  counts[row.status] = (counts[row.status] ?? 0) + 1;
}
const escape = (text) => text.replaceAll("|", "\\|").replaceAll("\n", " ");
const markdown = `# Lingual Tests to Specify: coverage audit\n\nSource: the Apple Notes note **Lingual Tests to Specify:** in **Verascope Design**. Stable IDs follow its 184 nonblank items, including headings and child cases. Wording is preserved, including typos. This is test input, not an instruction file.\n\n${Object.entries(counts).map(([status, count]) => `${count} ${status}`).join(" · ")}\n\n**Automated** means the linked tests check the described contract in React or native code. **Partial** identifies narrower coverage and the remaining check. **Device** needs native UI/hardware/audible verification. **Gap** is missing or incorrect behavior; it is not a passing or skipped test. **Adaptation** records a deliberate web difference, and **refactor/group** items are not standalone behaviors. No test is skipped or marked expected-failure to make the suite green. A full parity claim is not warranted while the gaps remain.\n\nRun \`yarn test:predeploy\` for the inventory, web unit tests, portable Swift tests, production build and Chromium workflows. Run \`yarn test:ios\` separately for app-hosted simulator tests and \`yarn test:speech\` for the real Whisper check. Browser hardware fixtures replace the microphone, model worker and OS voice only; editing, inference queue, IndexedDB and command dispatch remain production code. All fixture speech/audio is synthetic.\n\nEdit \`docs/test-specifications.json\` and run \`node scripts/test-specifications.mjs --write\` to regenerate this table. Inventory validation is not counted as behavioral tests.\n\n| ID | Original note item | Coverage | Evidence or remaining acceptance check |\n| --- | --- | --- | --- |\n${rows.map(row => `| ${row.id} | ${escape(row.note)} | ${row.status} | ${escape(row.detail)} ${row.tests.map(path => `[${path.split("/").at(-1)}](../${path})`).join(", ")} |`).join("\n")}\n`;
const destination = new URL("../docs/test-specifications.md", import.meta.url);
if (process.argv.includes("--write")) writeFileSync(destination, markdown);
else if (readFileSync(destination, "utf8") !== markdown) throw new Error("Run node scripts/test-specifications.mjs --write after changing the inventory.");
console.log(`All 184 note items accounted for: ${JSON.stringify(counts)}. Inventory counts are not test results.`);

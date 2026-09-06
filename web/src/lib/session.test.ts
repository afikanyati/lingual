import { expect, it } from "vitest";
import { restoreSession } from "./session";
import { createEntry } from "./editor";

it("restores the selected older entry and its caret without changing recorded content", () => {
  const entries = [
    createEntry(),
    { ...createEntry(), text: "one two", selection: { start: 7, end: 7 } },
  ];
  const restored = restoreSession(
    entries,
    JSON.stringify({ entryId: entries[1].id, selection: { start: 4, end: 7 } }),
  );
  expect(restored?.id).toBe(entries[1].id);
  expect(restored?.selection).toEqual({ start: 4, end: 7 });
  expect(restored?.text).toBe("one two");
  expect(entries[1].selection).toEqual({ start: 7, end: 7 });
});
it("ignores deleted entries and malformed saved sessions, and clamps stale selections", () => {
  const entry = { ...createEntry(), text: "one two" };
  for (const raw of [
    null,
    "broken",
    "null",
    "{}",
    JSON.stringify({ entryId: "deleted" }),
  ])
    expect(restoreSession([entry], raw)).toBeUndefined();
  expect(
    restoreSession(
      [entry],
      JSON.stringify({ entryId: entry.id, selection: { start: -3, end: 80 } }),
    )?.selection,
  ).toEqual({ start: 0, end: 7 });
  expect(
    restoreSession(
      [entry],
      JSON.stringify({
        entryId: entry.id,
        selection: { start: "three", end: 4 },
      }),
    ),
  ).toBeUndefined();
});

import { spokenWordRanges } from "./punctuation";
import { recordedSelection } from "./audio-integrity";
import type { Entry, TextSelection, TextSnapshot } from "../interfaces/entry";

export function createEntry(): Entry {
  const now = new Date().toISOString();
  return {
    id: crypto.randomUUID(),
    title: "",
    text: "",
    spans: [],
    selection: { start: 0, end: 0 },
    createdAt: now,
    updatedAt: now,
    history: [],
    future: [],
    clipIds: [],
  };
}
export function selectionAt(
  text: string,
  start: number,
  end: number,
): TextSelection {
  const left = Math.max(0, Math.min(text.length, Math.min(start, end)));
  return {
    start: left,
    end: Math.max(left, Math.min(text.length, Math.max(start, end))),
  };
}
export const snapshot = (entry: Entry): TextSnapshot => ({
  text: entry.text,
  selection: { ...entry.selection },
  spans: entry.spans.map((span) => ({ ...span })),
  lastCommit: entry.lastCommit,
  commits: entry.commits?.map((range) => ({ ...range })),
  selectionScale: entry.selectionScale,
});

/** Store the state before the edit, including the empty entry and its caret. */
export function replaceRange(
  entry: Entry,
  start: number,
  end: number,
  replacement: string,
  recordUnchanged = false,
): Entry {
  const range = recordedSelection(entry.text, { start, end }, entry.spans);
  const text =
    entry.text.slice(0, range.start) +
    replacement +
    entry.text.slice(range.end);
  // Identical replacement speech can still change source audio and must have an undo snapshot.
  if (text === entry.text && !recordUnchanged) return entry;
  const caret = range.start + replacement.length;
  // A touched word loses its audio association; unaffected words keep their exact source timing.
  const delta = replacement.length - (range.end - range.start);
  const spans = entry.spans.flatMap((span) => {
    if (span.end <= range.start) return [span];
    if (span.start >= range.end)
      return [{ ...span, start: span.start + delta, end: span.end + delta }];
    return [];
  });
  // Keep all surviving commit ranges: rolling back the newest one must reveal the previous commit.
  const commits = (entry.commits ?? (entry.lastCommit ? [entry.lastCommit] : [])).flatMap((commit) => {
    const surviving = entry.spans.filter((span) => span.start < commit.end && span.end > commit.start
      && (span.end <= range.start || span.start >= range.end));
    if (!surviving.length) return [];
    const first = surviving[0];
    const last = surviving.at(-1)!;
    return [{ start: first.start + (first.start >= range.end ? delta : 0),
      end: last.end + (last.start >= range.end ? delta : 0) }];
  });
  return {
    ...entry,
    text,
    spans,
    commits,
    lastCommit: commits.at(-1),
    selectionScale: undefined,
    selection: { start: caret, end: caret },
    history: [...entry.history.slice(-99), snapshot(entry)],
    future: [],
    updatedAt: new Date().toISOString(),
  };
}

export function undo(entry: Entry): Entry {
  const previous = entry.history.at(-1);
  if (!previous) return entry;
  return {
    ...entry,
    ...previous,
    lastCommit: previous.lastCommit,
    commits: previous.commits,
    selectionScale: previous.selectionScale,
    history: entry.history.slice(0, -1),
    future: [...entry.future, snapshot(entry)],
    updatedAt: new Date().toISOString(),
  };
}
export function redo(entry: Entry): Entry {
  const next = entry.future.at(-1);
  if (!next) return entry;
  return {
    ...entry,
    ...next,
    lastCommit: next.lastCommit,
    commits: next.commits,
    selectionScale: next.selectionScale,
    history: [...entry.history, snapshot(entry)],
    future: entry.future.slice(0, -1),
    updatedAt: new Date().toISOString(),
  };
}
export function wordCount(text: string): number {
  return spokenWordRanges(text).length;
}
export function entryTitle(entry: Entry): string {
  return (
    entry.title.trim() ||
    `Entry ${new Date(entry.createdAt).toLocaleDateString()} at ${new Date(entry.createdAt).toLocaleTimeString()}`
  );
}

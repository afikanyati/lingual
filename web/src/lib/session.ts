import type { Entry } from "../interfaces/entry";
import type { ReviewSession } from "../interfaces/session";
import { SelectionScale } from "../enums/selection";

/** Restore only a valid local entry and bounded cursor; stale session data must never hide saved entries. */
export function restoreSession(
  entries: Entry[],
  raw: string | null,
): Entry | undefined {
  if (!raw) return undefined;
  try {
    const session: Partial<ReviewSession> | null = JSON.parse(raw);
    const selection = session?.selection;
    const entry = entries.find((item) => item.id === session?.entryId);
    if (
      !entry ||
      !selection ||
      !Number.isFinite(selection.start) ||
      !Number.isFinite(selection.end)
    )
      return undefined;
    const start = Math.max(0, Math.min(entry.text.length, selection.start));
    const end = Math.max(start, Math.min(entry.text.length, selection.end));
    return {
      ...entry,
      selection: { start, end },
      selectionScale: Object.values(SelectionScale).includes(
        session!.selectionScale!,
      )
        ? session!.selectionScale
        : undefined,
    };
  } catch {
    return undefined;
  }
}

import { useEffect, useState } from "react";

// ** IMPORTANT **: Keep in sync with the compact layout breakpoint in src/styles.css.
const COMPACT_LAYOUT = "(max-width: 900px)";

/** Keep the compact library out of keyboard navigation when closed, and contain focus when open. */
export function useLibraryDrawer(dialogOpen: boolean) {
  const [compactLayout, setCompactLayout] = useState(
    () => window.matchMedia(COMPACT_LAYOUT).matches,
  );
  const [mobileLibrary, setMobileLibrary] = useState(false);

  useEffect(() => {
    const media = window.matchMedia(COMPACT_LAYOUT);
    const changed = () => {
      setCompactLayout(media.matches);
      if (!media.matches) setMobileLibrary(false);
    };
    media.addEventListener("change", changed);
    return () => media.removeEventListener("change", changed);
  }, []);

  useEffect(() => {
    if (!dialogOpen && !(compactLayout && mobileLibrary)) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = previous;
    };
  }, [compactLayout, mobileLibrary, dialogOpen]);

  useEffect(() => {
    if (!compactLayout || !mobileLibrary) return;
    const library = document.getElementById("entry-library");
    library?.querySelector<HTMLElement>(".mobile-library-close")?.focus();
    const keydown = (event: KeyboardEvent) => {
      // A dialog opened from the drawer owns keyboard interaction until dismissed.
      if (document.querySelector(".modal")) return;
      if (event.key === "Escape") {
        event.preventDefault();
        setMobileLibrary(false);
        return;
      }
      if (event.key !== "Tab") return;
      const controls = Array.from(
        library?.querySelectorAll<HTMLElement>(
          "a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled)",
        ) ?? [],
      ).filter((element) => element.getClientRects().length > 0);
      const first = controls[0];
      const last = controls.at(-1);
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    document.addEventListener("keydown", keydown);
    return () => {
      document.removeEventListener("keydown", keydown);
      if (window.matchMedia(COMPACT_LAYOUT).matches)
        document.querySelector<HTMLElement>(".mobile-library-toggle")?.focus();
    };
  }, [compactLayout, mobileLibrary]);

  return { compactLayout, mobileLibrary, setMobileLibrary };
}

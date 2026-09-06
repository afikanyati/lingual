import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { ButtonProps, TooltipPosition } from "../../interfaces/button";

/** Explain every action on hover or keyboard focus without changing its accessible name or layout. */
export function Button({ tooltip, children, ...props }: ButtonProps) {
  const tooltipId = useId();
  const button = useRef<HTMLButtonElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [position, setPosition] = useState<TooltipPosition>();

  function hideTooltip() {
    clearTimeout(timer.current);
    setPosition(undefined);
  }

  function showTooltip() {
    clearTimeout(timer.current);
    if (!button.current) return;
    const bounds = button.current.getBoundingClientRect();
    const halfWidth = Math.min(280, window.innerWidth - 16) / 2;
    const above = bounds.top > 110;
    setPosition({
      left: Math.max(
        halfWidth + 8,
        Math.min(
          window.innerWidth - halfWidth - 8,
          bounds.left + bounds.width / 2,
        ),
      ),
      top: above ? bounds.top - 8 : bounds.bottom + 8,
      above,
    });
  }

  useEffect(() => () => clearTimeout(timer.current), []);
  useEffect(() => {
    if (!position) return;
    // A tooltip must not remain detached from its button after scrolling, resizing, or pressing Escape.
    const dismissOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") hideTooltip();
    };
    window.addEventListener("scroll", hideTooltip, true);
    window.addEventListener("resize", hideTooltip);
    document.addEventListener("keydown", dismissOnEscape);
    return () => {
      window.removeEventListener("scroll", hideTooltip, true);
      window.removeEventListener("resize", hideTooltip);
      document.removeEventListener("keydown", dismissOnEscape);
    };
  }, [position]);

  return (
    <>
      <button
        {...props}
        ref={button}
        data-tooltip={tooltip}
        aria-describedby={
          [props["aria-describedby"], position ? tooltipId : undefined]
            .filter(Boolean)
            .join(" ") || undefined
        }
        onPointerEnter={(event) => {
          props.onPointerEnter?.(event);
          if (event.pointerType !== "touch")
            timer.current = setTimeout(showTooltip, 350);
        }}
        onPointerLeave={(event) => {
          props.onPointerLeave?.(event);
          hideTooltip();
        }}
        onFocus={(event) => {
          props.onFocus?.(event);
          clearTimeout(timer.current);
          // Focus can scroll an off-screen action into view. Measure after that initial scroll settles.
          timer.current = setTimeout(showTooltip, 100);
        }}
        onBlur={(event) => {
          props.onBlur?.(event);
          hideTooltip();
        }}
        onClick={(event) => {
          hideTooltip();
          props.onClick?.(event);
        }}
      >
        {children}
      </button>
      {position &&
        createPortal(
          <div
            id={tooltipId}
            role="tooltip"
            className="button-tooltip"
            style={{
              left: position.left,
              top: position.top,
              transform: position.above
                ? "translate(-50%, -100%)"
                : "translateX(-50%)",
            }}
          >
            {tooltip}
          </div>,
          document.body,
        )}
    </>
  );
}

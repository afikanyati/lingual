import { useEffect, useRef, useState } from "react";
import { HeadphoneStatus } from "../enums/headphones";
import { HeadphoneMonitor } from "../lib/headphone-detection";

/** Observe system audio output without requesting another microphone or storing a mode. */
export function useHeadphones() {
  const [status, setStatus] = useState(HeadphoneStatus.Unknown);
  const connected = useRef(false);
  const monitor = useRef<HeadphoneMonitor | undefined>(undefined);
  useEffect(() => {
    const media = navigator.mediaDevices;
    const observer = new HeadphoneMonitor(
      () => media?.enumerateDevices?.() ?? Promise.resolve([]),
      (next) => {
        connected.current = next === HeadphoneStatus.Headphones;
        setStatus(next);
      },
    );
    monitor.current = observer;
    const refresh = () => {
      if (!document.hidden) void observer.refresh();
    };
    media?.addEventListener("devicechange", refresh);
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    // Some browsers do not notify when the default changes among already connected outputs.
    const timer = setInterval(refresh, 3000);
    refresh();
    return () => {
      observer.dispose();
      clearInterval(timer);
      media?.removeEventListener("devicechange", refresh);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, []);
  return { status, connected, refresh: () => monitor.current?.refresh() };
}

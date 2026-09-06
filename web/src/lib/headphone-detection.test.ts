import { expect, it, vi } from "vitest";
import { detectHeadphones, HeadphoneMonitor } from "./headphone-detection";
import type { AudioDeviceDescription } from "../interfaces/headphones";

const output = (
  label: string,
  deviceId = "default",
  groupId = "output",
): AudioDeviceDescription => ({
  kind: "audiooutput",
  label,
  deviceId,
  groupId,
});

it("recognizes named headphone outputs, not their microphones or generic Bluetooth speakers", () => {
  for (const label of [
    "Default - External Headphones",
    "Default - Afika’s AirPods Pro",
    "USB Headset",
    "Bluetooth Earbuds",
  ])
    expect(detectHeadphones([output(label)])).toBe("headphones");
  expect(detectHeadphones([output("MacBook Pro Speakers")])).toBe("speakers");
  expect(detectHeadphones([{ ...output("AirPods"), kind: "audioinput" }])).toBe(
    "unknown",
  );
  expect(detectHeadphones([output("Bluetooth audio")])).toBe("unknown");
  expect(detectHeadphones([output("Speakers / Headphones (Realtek)")])).toBe(
    "unknown",
  );
});

it("uses the system output rather than assuming an available headset is being used", () => {
  expect(
    detectHeadphones([output("Speakers"), output("AirPods", "other")]),
  ).toBe("speakers");
  expect(
    detectHeadphones([output("Default"), output("AirPods", "other")]),
  ).toBe("headphones");
  expect(
    detectHeadphones([
      output("Default"),
      output("AirPods", "other", "different"),
    ]),
  ).toBe("unknown");
  expect(detectHeadphones([output("AirPods", "other")])).toBe("unknown");
  expect(detectHeadphones([output("")])).toBe("unknown");
  expect(detectHeadphones([])).toBe("unknown");
});

it("ignores old enumeration responses after disconnection and after disposal", async () => {
  let complete!: (devices: AudioDeviceDescription[]) => void;
  const read = vi
    .fn()
    .mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          complete = resolve;
        }),
    )
    .mockResolvedValue([output("Speakers")]);
  const changed = vi.fn();
  const monitor = new HeadphoneMonitor(read, changed);
  const old = monitor.refresh();
  await monitor.refresh();
  complete([output("AirPods")]);
  await old;
  expect(changed.mock.calls).toEqual([["speakers"]]);
  monitor.dispose();
  await monitor.refresh();
  expect(changed).toHaveBeenCalledTimes(1);
});

it("revokes headphone detection when enumeration fails", async () => {
  const read = vi
    .fn()
    .mockResolvedValueOnce([output("AirPods")])
    .mockRejectedValue(new Error("permission revoked"));
  const changed = vi.fn();
  const monitor = new HeadphoneMonitor(read, changed);
  await monitor.refresh();
  await monitor.refresh();
  expect(changed.mock.calls).toEqual([["headphones"], ["unknown"]]);
});

import { HeadphoneStatus } from "../enums/headphones";
import type { AudioDeviceDescription } from "../interfaces/headphones";

/** Infer only a recognizable default output. Available headsets and input devices
 * do not establish where speech synthesis will play. Ambiguous names stay unknown.
 * Device labels are a best-effort browser signal, not proof that headphones are worn.
 */
export function detectHeadphones(
  devices: AudioDeviceDescription[],
): HeadphoneStatus {
  const outputs = devices.filter((device) => device.kind === "audiooutput");
  const selected = outputs.find((device) => device.deviceId === "default");
  if (!selected?.label) return HeadphoneStatus.Unknown;
  let label = selected.label;
  if (/^default$/i.test(label.trim()) && selected.groupId) {
    const matches = outputs.filter(
      (device) =>
        device.deviceId !== "default" && device.groupId === selected.groupId,
    );
    if (matches.length === 1) label = matches[0].label;
  }
  const headphones =
    /\b(headphones?|headsets?|earphones?|earbuds?|airpods|earpods|powerbeats)\b/i.test(
      label,
    );
  const speakers = /\b(speakers?|hdmi|displayport|monitor|television)\b/i.test(
    label,
  );
  if (headphones && !speakers) return HeadphoneStatus.Headphones;
  if (speakers && !headphones) return HeadphoneStatus.Speakers;
  return HeadphoneStatus.Unknown;
}

/** A newer device snapshot or teardown always supersedes a slower enumeration. */
export class HeadphoneMonitor {
  private generation = 0;
  private disposed = false;

  constructor(
    private read: () => Promise<AudioDeviceDescription[]>,
    private changed: (status: HeadphoneStatus) => void,
  ) {}

  async refresh(): Promise<void> {
    if (this.disposed) return;
    const generation = ++this.generation;
    let status = HeadphoneStatus.Unknown;
    try {
      status = detectHeadphones(await this.read());
    } catch {
      /* Missing permission or an unsupported API must not retain an old detection. */
    }
    if (!this.disposed && generation === this.generation) this.changed(status);
  }

  dispose(): void {
    this.disposed = true;
    this.generation++;
  }
}

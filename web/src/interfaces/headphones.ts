import type { Preferences } from "./workspace";
import type { HeadphoneStatus } from "../enums/headphones";

/** The browser exposes names and groups, but no standardized headphone device type. */
export interface AudioDeviceDescription {
  kind: MediaDeviceKind;
  label: string;
  deviceId: string;
  groupId: string;
}

export interface HeadphoneReminderContext {
  preferences: Preferences;
  headphoneStatus?: HeadphoneStatus;
  listening?: boolean;
  selection?: boolean;
  browsing?: boolean;
  handsFreePlayback?: boolean;
  settingsOpen?: boolean;
  requestedFeature?: "passiveEcho" | "voiceFeedback";
}

export interface HeadphoneReminderProps {
  message: string;
}

import type { Preferences } from "./workspace";
export interface BooleanSettingDescription {
  key: keyof Preferences;
  label: string;
  description: string;
}

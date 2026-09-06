import { Headphones } from "lucide-react";
import type { HeadphoneReminderProps } from "../../interfaces/headphones";

export function HeadphoneReminder({ message }: HeadphoneReminderProps) {
  if (!message) return null;
  return (
    <div
      className="headphone-reminder"
      role="status"
      aria-label="Headphones needed"
    >
      <Headphones size={18} aria-hidden="true" />
      <span>{message}</span>
    </div>
  );
}

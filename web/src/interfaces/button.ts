import type { ButtonHTMLAttributes } from "react";

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  tooltip: string;
}

export interface TooltipPosition {
  left: number;
  top: number;
  above: boolean;
}
